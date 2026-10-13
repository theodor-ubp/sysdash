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

    var ecpuMaxMHz: Double { Double(ecpuFreqs.max() ?? 3000) }
    var pcpuMaxMHz: Double { Double(pcpuFreqs.max() ?? 4500) }
    var gpuMaxMHz: Double { Double(gpuFreqs.compactMap { $0 > 0 ? $0 : nil }.max() ?? 1500) }
    var coreLabel: String { "\(ecpuCores)\(ecpuLabel)+\(pcpuCores)\(pcpuLabel)+\(gpuCores)GPU" }
}

struct MacmonOutput: Codable {
    struct TempMetrics: Codable {
        let cpuTempAvg: Double?
        let gpuTempAvg: Double?
    }
    struct MemMetrics: Codable {
        let ramTotal: UInt64
        let ramUsage: UInt64
        let swapTotal: UInt64
        let swapUsage: UInt64
    }

    let temp: TempMetrics
    let memory: MemMetrics
    let ecpuFreqMhz: Double
    let pcpuFreqMhz: Double
    let gpuFreqMhz: Double
    let ecpuActiveRatio: Double
    let pcpuActiveRatio: Double
    let cpuActiveRatio: Double
    let gpuActiveRatio: Double
    let cpuPower: Double      // Watts
    let gpuPower: Double
    let anePower: Double
    let allPower: Double
    let sysPower: Double
    let ramPower: Double
    let gpuRamPower: Double
    let soc: MacmonSocInfo?

    var ecpuFreqMHz: Double  { ecpuFreqMhz }
    var ecpuPct: Double      { ecpuActiveRatio * 100 }
    var pcpuFreqMHz: Double  { pcpuFreqMhz }
    var pcpuPct: Double      { pcpuActiveRatio * 100 }
    var gpuFreqMHz: Double   { gpuFreqMhz }
    var gpuPct: Double       { gpuActiveRatio * 100 }
    var cpuPct: Double       { cpuActiveRatio * 100 }
    var ramUsedGB: Double    { Double(memory.ramUsage) / 1_073_741_824 }
    var ramTotalGB: Double   { Double(memory.ramTotal) / 1_073_741_824 }
    var swapUsedGB: Double   { Double(memory.swapUsage) / 1_073_741_824 }
    var swapTotalGB: Double  { Double(memory.swapTotal) / 1_073_741_824 }
    var ramPct: Double       { ramTotalGB > 0 ? (ramUsedGB / ramTotalGB) * 100 : 0 }
}

func formatTemperature(_ value: Double?, suffix: String = "°") -> String {
    value.map { String(format: "%.0f%@", $0, suffix) } ?? "—"
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
    @Published var macmon: MacmonOutput? {
        didSet { if let soc = macmon?.soc, socInfo != soc { socInfo = soc } }
    }
    @Published var socInfo: MacmonSocInfo?
    @Published var macmonError: String?
    @Published var macmonRunning = false

    // Battery (polled separately via IOKit)
    @Published var hasBattery = false
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
            guard intervalMs != oldValue else { return }
            defaults.set(intervalMs, forKey: "sysdash.intervalMs")
            restartMacmon()
        }
    }

    private let defaults: UserDefaults
    private let macmonPath: String?
    private var macmonProcess: Process?
    private var auxSub: AnyCancellable?
    private var generation = UUID()
    private var macmonStderr = ""

    init(macmonPath: String? = nil, defaults: UserDefaults = .standard) {
        self.macmonPath = macmonPath
        self.defaults = defaults
        let saved = defaults.integer(forKey: "sysdash.intervalMs")
        intervalMs = [500, 1000, 2000, 5000].contains(saved) ? saved : 1000
        startMacmon()
        fetchBattery()
        fetchDisk()
        auxSub = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fetchBattery(); self?.fetchDisk() }
    }

    // MARK: - macmon lifecycle

    private func startMacmon() {
        guard let path = macmonPath ?? findMacmon() else {
            macmonError = "macmon binary not found. Reinstall UP Sysdash."
            macmonRunning = false
            return
        }

        let p = Process()
        generation = UUID()
        let token = generation
        let output = Pipe()
        let errors = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["pipe", "--soc-info", "-i", "\(max(500, intervalMs))"]
        p.standardOutput = output
        p.standardError = errors
        macmonStderr = ""

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.macmonProcess = nil
                self.generation = UUID()
                let retryToken = self.generation
                self.macmonRunning = false
                self.macmon = nil
                self.macmonError = self.macmonStderr.isEmpty
                    ? "macmon exited (status \(proc.terminationStatus)). Retrying…"
                    : self.macmonStderr
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.generation == retryToken else { return }
                    self.startMacmon()
                }
            }
        }

        do {
            try p.run()
            macmonProcess = p
            macmonError = nil
        } catch {
            macmonError = "Failed to launch macmon: \(error.localizedDescription)"
            macmonRunning = false
            return
        }

        // Each reader owns its decoder and buffer. Generation checks prevent an
        // old helper's queued output from overwriting a restarted helper's data.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var pending = Data()
            while true {
                let chunk = output.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    guard !line.isEmpty else { continue }
                    do {
                        let metrics = try decoder.decode(MacmonOutput.self, from: line)
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.macmon = metrics
                            self.macmonError = nil
                            self.macmonRunning = true
                            self.recordHistory(metrics)
                            self.updateNetwork()
                        }
                    } catch {
                        let message = "Cannot read macmon metrics: \(error.localizedDescription)"
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.macmonRunning = false
                            self.macmon = nil
                            self.macmonError = message
                        }
                    }
                }
            }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let chunk = errors.fileHandleForReading.availableData
                guard !chunk.isEmpty else { break }
                let message = String(decoding: chunk, as: UTF8.self)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.macmonStderr = String((self.macmonStderr + message).suffix(4096))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    private func stopMacmon() {
        generation = UUID()
        macmonProcess?.terminationHandler = nil
        if macmonProcess?.isRunning == true { macmonProcess?.terminate() }
        macmonProcess = nil
        macmonRunning = false
        macmon = nil
    }

    func shutdown() {
        auxSub?.cancel()
        auxSub = nil
        stopMacmon()
    }

    private func restartMacmon() {
        stopMacmon()
        startMacmon()
    }

    // MARK: - History recording

    private func recordHistory(_ m: MacmonOutput) {
        cpuBuf.push(m.cpuPct / 100)
        ecpuBuf.push(m.ecpuPct / 100)
        pcpuBuf.push(m.pcpuPct / 100)
        gpuBuf.push(m.gpuPct / 100)
        if let temperature = m.temp.cpuTempAvg { cpuTempBuf.push(temperature / 100) }
        if let temperature = m.temp.gpuTempAvg { gpuTempBuf.push(temperature / 100) }
        cpuPowerBuf.push(m.cpuPower / 30)
        gpuPowerBuf.push(m.gpuPower / 20)
        anePowerBuf.push(m.anePower / 8)
        sysPowerBuf.push(m.sysPower / 65)
        ramBuf.push(m.ramPct / 100)

        cpuHistory      = cpuBuf.samples
        ecpuHistory     = ecpuBuf.samples
        pcpuHistory     = pcpuBuf.samples
        gpuHistory      = gpuBuf.samples
        cpuTempHistory  = m.temp.cpuTempAvg == nil ? [] : cpuTempBuf.samples
        gpuTempHistory  = m.temp.gpuTempAvg == nil ? [] : gpuTempBuf.samples
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
            let upBps   = Double(tx >= lastNetTx ? tx - lastNetTx : 0) / dt
            let downBps = Double(rx >= lastNetRx ? rx - lastNetRx : 0) / dt
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
            hasBattery = false; batteryLevel = 0; isOnBattery = false; isCharging = false
            return
        }
        if let curr = desc[kIOPSCurrentCapacityKey] as? Int,
           let max  = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            hasBattery = true
            batteryLevel = Double(curr) / Double(max) * 100
        } else {
            hasBattery = false
            batteryLevel = 0
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
