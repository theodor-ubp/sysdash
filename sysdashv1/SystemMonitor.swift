import Foundation
import Combine
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - macmon JSON types

struct MacmonSocInfo: Codable, Equatable {
    let chipName: String
    let macModel: String
    let memoryGb: UInt16
    let ecpuCores: UInt8
    let pcpuCores: UInt8
    let gpuCores: UInt8
    let ecpuLabel: String
    let pcpuLabel: String
    let ecpuFreqs: [UInt32]
    let pcpuFreqs: [UInt32]
    let gpuFreqs: [UInt32]

    var ecpuMaxMHz: Double { Double(ecpuFreqs.last ?? 3000) }
    var pcpuMaxMHz: Double { Double(pcpuFreqs.last ?? 4500) }
    var gpuMaxMHz: Double { Double(gpuFreqs.compactMap { $0 > 0 ? $0 : nil }.max() ?? 1500) }
    var coreLabel: String { "\(ecpuCores)\(ecpuLabel)+\(pcpuCores)\(pcpuLabel)+\(gpuCores)GPU" }
}

struct MacmonOutput: Codable {
    struct TempMetrics: Codable {
        let cpuTempAvg: Double
        let gpuTempAvg: Double
    }
    struct MemMetrics: Codable {
        let ramTotal: UInt64
        let ramUsage: UInt64
        let swapTotal: UInt64
        let swapUsage: UInt64
    }

    let temp: TempMetrics
    let memory: MemMetrics
    let ecpuUsage: [Double]   // [freq_mhz, usage_ratio 0-1]
    let pcpuUsage: [Double]   // [freq_mhz, usage_ratio 0-1]
    let cpuUsagePct: Double   // combined weighted 0-1
    let gpuUsage: [Double]    // [freq_mhz, usage_ratio 0-1]
    let cpuPower: Double      // Watts
    let gpuPower: Double
    let anePower: Double
    let allPower: Double
    let sysPower: Double
    let ramPower: Double
    let gpuRamPower: Double
    let soc: MacmonSocInfo?

    var ecpuFreqMHz: Double  { ecpuUsage.first ?? 0 }
    var ecpuPct: Double      { (ecpuUsage.count > 1 ? ecpuUsage[1] : 0) * 100 }
    var pcpuFreqMHz: Double  { pcpuUsage.first ?? 0 }
    var pcpuPct: Double      { (pcpuUsage.count > 1 ? pcpuUsage[1] : 0) * 100 }
    var gpuFreqMHz: Double   { gpuUsage.first ?? 0 }
    var gpuPct: Double       { (gpuUsage.count > 1 ? gpuUsage[1] : 0) * 100 }
    var cpuPct: Double       { cpuUsagePct * 100 }
    var ramUsedGB: Double    { Double(memory.ramUsage) / 1_073_741_824 }
    var ramTotalGB: Double   { Double(memory.ramTotal) / 1_073_741_824 }
    var swapUsedGB: Double   { Double(memory.swapUsage) / 1_073_741_824 }
    var swapTotalGB: Double  { Double(memory.swapTotal) / 1_073_741_824 }
    var ramPct: Double       { ramTotalGB > 0 ? (ramUsedGB / ramTotalGB) * 100 : 0 }
}

// MARK: - Ring buffer (60 samples, 0–1 normalised)

private struct HistoryBuf {
    private var buf   = [Double](repeating: 0, count: 60)
    private var head  = 0
    private var count = 0

    mutating func push(_ v: Double) {
        buf[head] = min(max(v, 0), 1)
        head = (head + 1) % 60
        if count < 60 { count += 1 }
    }

    var samples: [Double] {
        guard count > 0 else { return [] }
        let start = count < 60 ? 0 : head
        return (0..<count).map { buf[(start + $0) % 60] }
    }
}

// MARK: - SystemMonitor

class SystemMonitor: ObservableObject {

    // macmon-powered metrics
    @Published var macmon: MacmonOutput?
    @Published var macmonError: String?
    @Published var macmonRunning = false

    // Battery (polled separately via IOKit)
    @Published var batteryLevel: Double = 0
    @Published var isOnBattery = false
    @Published var isCharging = false

    // Disk (polled separately via FileManager)
    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0

    // History sparklines (0–1 normalised, 60 samples each)
    @Published var cpuHistory:      [Double] = []
    @Published var ecpuHistory:     [Double] = []
    @Published var pcpuHistory:     [Double] = []
    @Published var gpuHistory:      [Double] = []
    @Published var cpuTempHistory:  [Double] = []
    @Published var gpuTempHistory:  [Double] = []
    @Published var cpuPowerHistory: [Double] = []
    @Published var gpuPowerHistory: [Double] = []
    @Published var anePowerHistory: [Double] = []
    @Published var sysPowerHistory: [Double] = []
    @Published var ramHistory:      [Double] = []
    @Published var netUpHistory:    [Double] = []
    @Published var netDownHistory:  [Double] = []

    // Network throughput
    @Published var networkUpBps:   Double = 0
    @Published var networkDownBps: Double = 0

    // Private history ring-buffers
    private var cpuBuf      = HistoryBuf()
    private var ecpuBuf     = HistoryBuf()
    private var pcpuBuf     = HistoryBuf()
    private var gpuBuf      = HistoryBuf()
    private var cpuTempBuf  = HistoryBuf()
    private var gpuTempBuf  = HistoryBuf()
    private var cpuPowerBuf = HistoryBuf()
    private var gpuPowerBuf = HistoryBuf()
    private var anePowerBuf = HistoryBuf()
    private var sysPowerBuf = HistoryBuf()
    private var ramBuf      = HistoryBuf()
    private var netUpBuf    = HistoryBuf()
    private var netDownBuf  = HistoryBuf()

    // Network delta state
    private var lastNetRx:   UInt64 = 0
    private var lastNetTx:   UInt64 = 0
    private var lastNetDate: Date   = .distantPast
    private var netPeakBps:  Double = 1_048_576   // adaptive ceiling (starts at 1 MB/s)

    // Refresh interval (ms)
    @Published var intervalMs: Int {
        didSet {
            UserDefaults.standard.set(intervalMs, forKey: "sysdash.intervalMs")
            restartMacmon()
        }
    }

    private let macmonPort = 19191
    private var macmonProcess: Process?
    private var pollSub: AnyCancellable?
    private var auxSub: AnyCancellable?
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init() {
        let saved = UserDefaults.standard.integer(forKey: "sysdash.intervalMs")
        intervalMs = saved > 100 ? saved : 1000
        startMacmon()
        fetchBattery()
        fetchDisk()
        auxSub = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchBattery(); self?.fetchDisk() }
    }

    // MARK: - macmon lifecycle

    private func startMacmon() {
        guard let path = findMacmon() else {
            macmonError = "macmon binary not found.\nInstall: brew install vladkens/tap/macmon\nor place binary at ~/Downloads/macmon/macmon"
            macmonRunning = false
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["serve", "--port", "\(macmonPort)", "-i", "\(max(500, intervalMs))"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.macmonProcess === proc else { return }
                self.macmonProcess = nil
                self.startMacmon()
            }
        }

        do {
            try p.run()
            macmonProcess = p
            macmonError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.startPolling()
            }
        } catch {
            macmonError = "Failed to launch macmon: \(error.localizedDescription)"
            macmonRunning = false
        }
    }

    private func stopMacmon() {
        pollSub?.cancel()
        pollSub = nil
        macmonProcess?.terminationHandler = nil
        macmonProcess?.terminate()
        macmonProcess = nil
        macmonRunning = false
    }

    private func restartMacmon() {
        stopMacmon()
        startMacmon()
    }

    private func startPolling() {
        let interval = TimeInterval(max(500, intervalMs)) / 1000.0
        pollSub = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let body = self.fetchViaSocket() else {
                DispatchQueue.main.async { self.macmonRunning = false }
                return
            }
            guard let m = try? self.decoder.decode(MacmonOutput.self, from: body) else { return }
            DispatchQueue.main.async {
                self.macmon = m
                self.macmonError = nil
                self.macmonRunning = true
                self.recordHistory(m)
                self.updateNetwork()
            }
        }
    }

    private func fetchViaSocket() -> Data? {
        let sockfd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sockfd >= 0 else { return nil }
        defer { Darwin.close(sockfd) }

        // 1.5 s send + receive timeout
        var tv = timeval(tv_sec: 1, tv_usec: 500_000)
        let tvLen = socklen_t(MemoryLayout<timeval>.size)
        Darwin.setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, tvLen)
        Darwin.setsockopt(sockfd, SOL_SOCKET, SO_SNDTIMEO, &tv, tvLen)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(macmonPort).bigEndian
        Darwin.inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
        let connected = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        let req = "GET /json HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n"
        _ = req.withCString { Darwin.send(sockfd, $0, Darwin.strlen($0), 0) }

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = Darwin.recv(sockfd, &buf, buf.count, 0)
            guard n > 0 else { break }
            response.append(contentsOf: buf.prefix(n))
        }

        let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
        guard let range = response.range(of: sep) else { return nil }
        let body = response[range.upperBound...]
        return body.isEmpty ? nil : Data(body)
    }

    // MARK: - History recording

    private func recordHistory(_ m: MacmonOutput) {
        cpuBuf.push(m.cpuPct / 100)
        ecpuBuf.push(m.ecpuPct / 100)
        pcpuBuf.push(m.pcpuPct / 100)
        gpuBuf.push(m.gpuPct / 100)
        cpuTempBuf.push(m.temp.cpuTempAvg / 100)
        gpuTempBuf.push(m.temp.gpuTempAvg / 100)
        cpuPowerBuf.push(m.cpuPower / 30)
        gpuPowerBuf.push(m.gpuPower / 20)
        anePowerBuf.push(m.anePower / 8)
        sysPowerBuf.push(m.sysPower / 65)
        ramBuf.push(m.ramPct / 100)

        cpuHistory      = cpuBuf.samples
        ecpuHistory     = ecpuBuf.samples
        pcpuHistory     = pcpuBuf.samples
        gpuHistory      = gpuBuf.samples
        cpuTempHistory  = cpuTempBuf.samples
        gpuTempHistory  = gpuTempBuf.samples
        cpuPowerHistory = cpuPowerBuf.samples
        gpuPowerHistory = gpuPowerBuf.samples
        anePowerHistory = anePowerBuf.samples
        sysPowerHistory = sysPowerBuf.samples
        ramHistory      = ramBuf.samples
    }

    // MARK: - Network monitoring

    private func updateNetwork() {
        let (rx, tx) = readNetworkBytes()
        let now = Date()
        let dt = now.timeIntervalSince(lastNetDate)

        if lastNetDate != .distantPast && dt > 0 {
            let upBps   = Double(tx &- lastNetTx) / dt
            let downBps = Double(rx &- lastNetRx) / dt
            networkUpBps   = max(0, upBps)
            networkDownBps = max(0, downBps)

            let peak = max(networkUpBps, networkDownBps)
            if peak > netPeakBps { netPeakBps = peak * 1.2 }
            else { netPeakBps = max(1_048_576, netPeakBps * 0.995) }

            netUpBuf.push(networkUpBps   / netPeakBps)
            netDownBuf.push(networkDownBps / netPeakBps)
            netUpHistory   = netUpBuf.samples
            netDownHistory = netDownBuf.samples
        }

        lastNetRx   = rx
        lastNetTx   = tx
        lastNetDate = now
    }

    private func readNetworkBytes() -> (rx: UInt64, tx: UInt64) {
        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(first) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let name = ifa.pointee.ifa_name,
                  String(cString: name) != "lo0"
            else { continue }

            if let dataPtr = ifa.pointee.ifa_data {
                let d = dataPtr.bindMemory(to: if_data.self, capacity: 1).pointee
                totalRx &+= UInt64(d.ifi_ibytes)
                totalTx &+= UInt64(d.ifi_obytes)
            }
        }
        return (totalRx, totalTx)
    }

    // MARK: - macmon binary discovery

    private func findMacmon() -> String? {
        let candidates = [
            Bundle.main.bundlePath + "/Contents/MacOS/macmon",
            Bundle.main.bundlePath + "/Contents/Resources/macmon",
            "/opt/homebrew/bin/macmon",
            "/usr/local/bin/macmon",
            "\(NSHomeDirectory())/.local/bin/macmon",
            "\(NSHomeDirectory())/Downloads/macmon/macmon",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Battery

    private func fetchBattery() {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
            let ps = list.first,
            let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any]
        else {
            batteryLevel = 0; isOnBattery = false; isCharging = false
            return
        }
        if let curr = desc[kIOPSCurrentCapacityKey] as? Int,
           let max  = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            batteryLevel = Double(curr) / Double(max) * 100
        }
        if let state = desc[kIOPSPowerSourceStateKey] as? String {
            isOnBattery = state == kIOPSBatteryPowerValue
        }
        isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
    }

    // MARK: - Disk

    private func fetchDisk() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()) else { return }
        diskFreeGB  = (attrs[.systemFreeSize]  as? NSNumber)?.doubleValue ?? 0
        diskFreeGB  /= 1_073_741_824
        diskTotalGB = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
        diskTotalGB /= 1_073_741_824
    }

    deinit {
        stopMacmon()
    }
}
