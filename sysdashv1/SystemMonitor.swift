import Foundation
import Combine
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - macmon JSON types

struct MacmonCPUTierInfo: Decodable, Equatable, Identifiable {
    let label: String
    let cores: UInt8
    let freqs: [UInt32]

    var id: String { label }
    var displayName: String { label == "_" ? "CPU CORES" : "\(label)-CORES" }
    var maxMHz: Double? { freqs.filter { $0 > 0 }.max().map(Double.init) }
}

struct MacmonCPUTierMetrics: Decodable {
    struct Core: Decodable {
        let coreId: UInt16
        let dieId: UInt8
    }
    let label: String
    let freqMhz: Double
    let activeRatio: Double
    let cores: [Core]?

    var percent: Double { activeRatio * 100 }
}

struct MacmonSocInfo: Decodable, Equatable {
    let chipName: String
    let macModel: String
    let memoryGb: UInt16
    let gpuCores: UInt8
    let gpuFreqs: [UInt32]
    let cpuTiers: [MacmonCPUTierInfo]
    let vm: Bool

    var gpuMaxMHz: Double? { gpuFreqs.filter { $0 > 0 }.max().map(Double.init) }
    var coreLabel: String {
        let cpu = cpuTiers.map { $0.label == "_" ? "\($0.cores) cores" : "\($0.cores)\($0.label)" }
        return (cpu + (gpuCores > 0 ? ["\(gpuCores)GPU"] : [])).joined(separator: "+")
    }

    private enum CodingKeys: String, CodingKey {
        case chipName, macModel, memoryGb, gpuCores, gpuFreqs, cpuTiers, vm
        case ecpuCores, pcpuCores, ecpuLabel, pcpuLabel, ecpuFreqs, pcpuFreqs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chipName = try c.decode(String.self, forKey: .chipName)
        macModel = try c.decode(String.self, forKey: .macModel)
        memoryGb = try c.decode(UInt16.self, forKey: .memoryGb)
        gpuCores = try c.decode(UInt8.self, forKey: .gpuCores)
        gpuFreqs = try c.decode([UInt32].self, forKey: .gpuFreqs)
        vm = try c.decodeIfPresent(Bool.self, forKey: .vm) ?? false
        if let tiers = try c.decodeIfPresent([MacmonCPUTierInfo].self, forKey: .cpuTiers), !tiers.isEmpty {
            cpuTiers = tiers
        } else {
            // macmon 0.9 compatibility. New helpers must use every canonical tier.
            cpuTiers = try [
                MacmonCPUTierInfo(label: c.decode(String.self, forKey: .ecpuLabel),
                                  cores: c.decode(UInt8.self, forKey: .ecpuCores),
                                  freqs: c.decode([UInt32].self, forKey: .ecpuFreqs)),
                MacmonCPUTierInfo(label: c.decode(String.self, forKey: .pcpuLabel),
                                  cores: c.decode(UInt8.self, forKey: .pcpuCores),
                                  freqs: c.decode([UInt32].self, forKey: .pcpuFreqs))
            ].filter { $0.cores > 0 }
        }
    }
}

struct MacmonOutput: Decodable {
    struct TempMetrics: Decodable {
        let cpuTempAvg: Double?
        let gpuTempAvg: Double?
    }
    struct MemMetrics: Decodable {
        let ramTotal: UInt64
        let ramUsage: UInt64
        let swapTotal: UInt64
        let swapUsage: UInt64
    }

    let temp: TempMetrics
    let memory: MemMetrics
    let cpuTiers: [MacmonCPUTierMetrics]?
    let ecpuFreqMhz: Double?
    let pcpuFreqMhz: Double?
    let gpuFreqMhz: Double
    let ecpuActiveRatio: Double?
    let pcpuActiveRatio: Double?
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

    var tiers: [MacmonCPUTierMetrics] {
        if let cpuTiers, !cpuTiers.isEmpty { return cpuTiers }
        return [
            MacmonCPUTierMetrics(label: soc?.cpuTiers.first?.label ?? "E", freqMhz: ecpuFreqMhz ?? 0,
                                 activeRatio: ecpuActiveRatio ?? 0, cores: nil),
            MacmonCPUTierMetrics(label: soc?.cpuTiers.last?.label ?? "P", freqMhz: pcpuFreqMhz ?? 0,
                                 activeRatio: pcpuActiveRatio ?? 0, cores: nil)
        ]
    }
    var ecpuFreqMHz: Double  { tiers.first?.freqMhz ?? 0 }
    var ecpuPct: Double      { (tiers.first?.activeRatio ?? 0) * 100 }
    var pcpuFreqMHz: Double  { tiers.last?.freqMhz ?? 0 }
    var pcpuPct: Double      { (tiers.last?.activeRatio ?? 0) * 100 }
    var gpuFreqMHz: Double   { gpuFreqMhz }
    var gpuPct: Double       { gpuActiveRatio * 100 }
    var cpuPct: Double       { cpuActiveRatio * 100 }
    var ramUsedGB: Double    { Double(memory.ramUsage) / 1_073_741_824 }
    var ramTotalGB: Double   { Double(memory.ramTotal) / 1_073_741_824 }
    var swapUsedGB: Double   { Double(memory.swapUsage) / 1_073_741_824 }
    var swapTotalGB: Double  { Double(memory.swapTotal) / 1_073_741_824 }
    var ramPct: Double       { ramTotalGB > 0 ? (ramUsedGB / ramTotalGB) * 100 : 0 }

    func validateTiers() throws {
        for labels in [tiers.map(\.label), soc?.cpuTiers.map(\.label) ?? []] {
            guard Set(labels).count == labels.count, !labels.contains(where: \.isEmpty) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "CPU tier labels must be unique and nonempty"))
            }
        }
    }
}

func formatTemperature(_ value: Double?, suffix: String = "°") -> String {
    value.map { String(format: "%.0f%@", $0, suffix) } ?? "—"
}

func formatFrequency(_ value: Double?) -> String {
    guard let value, value > 0 else { return "—" }
    return String(format: "%.0f MHz", value)
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
    @Published var cpuTierHistory: [String: [Double]] = [:]
    @Published var gpuHistory:      [Double] = []
    @Published var cpuTempHistory:  [Double] = []
    @Published var gpuTempHistory:  [Double] = []
    @Published var cpuPowerHistory: [Double] = []
    @Published var gpuPowerHistory: [Double] = []
    @Published var anePowerHistory: [Double] = []
    @Published var sysPowerHistory: [Double] = []
    @Published var ramHistory:      [Double] = []
    @Published var swapHistory:     [Double] = []
    @Published var batteryHistory:  [Double] = []
    @Published var diskFreeHistory: [Double] = []
    @Published var netUpHistory:    [Double] = []
    @Published var netDownHistory:  [Double] = []

    // Network throughput
    @Published var networkUpBps:   Double = 0
    @Published var networkDownBps: Double = 0

    // Private history ring-buffers
    private var cpuBuf      = HistoryBuf()
    private var tierBuffers: [String: HistoryBuf] = [:]
    private var gpuBuf      = HistoryBuf()
    private var cpuTempBuf  = HistoryBuf()
    private var gpuTempBuf  = HistoryBuf()
    private var cpuPowerBuf = HistoryBuf()
    private var gpuPowerBuf = HistoryBuf()
    private var anePowerBuf = HistoryBuf()
    private var sysPowerBuf = HistoryBuf()
    private var ramBuf      = HistoryBuf()
    private var swapBuf     = HistoryBuf()
    private var batteryBuf  = HistoryBuf()
    private var diskFreeBuf = HistoryBuf()
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
    private var watchdogSub: AnyCancellable?
    private var generation = UUID()
    private var macmonStderr = ""
    private var lastSampleDate = Date()
    private var isShutdown = false

    var powerAvailable: Bool { socInfo?.vm != true }
    var gpuAvailable: Bool { socInfo?.vm != true && socInfo?.gpuCores != 0 }
    var cpuTiers: [MacmonCPUTierInfo] {
        socInfo?.cpuTiers ?? macmon?.tiers.map {
            MacmonCPUTierInfo(label: $0.label, cores: UInt8(clamping: $0.cores?.count ?? 0), freqs: [])
        } ?? []
    }

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
        watchdogSub = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.macmonProcess != nil,
                      Date().timeIntervalSince(self.lastSampleDate) > max(5, Double(self.intervalMs) / 1000 * 3)
                else { return }
                self.recoverMacmon("macmon stopped sending metrics. Retrying…", token: self.generation)
            }
    }

    // MARK: - macmon lifecycle

    private func startMacmon() {
        guard !isShutdown else { return }
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
        lastSampleDate = Date()

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                let message = self.macmonStderr.isEmpty
                    ? "macmon exited (status \(proc.terminationStatus)). Retrying…"
                    : self.macmonStderr
                self.recoverMacmon(message, token: token)
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
                // A valid full snapshot is only a few KB. Bound faulty streams
                // so a helper missing its newline cannot grow memory forever.
                guard pending.count <= 1_048_576 else {
                    DispatchQueue.main.async { [weak self] in
                        self?.recoverMacmon("macmon sent an oversized metrics frame. Retrying…", token: token)
                    }
                    break
                }
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    guard !line.isEmpty else { continue }
                    do {
                        let metrics = try decoder.decode(MacmonOutput.self, from: line)
                        try metrics.validateTiers()
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.lastSampleDate = Date()
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

    private func recoverMacmon(_ message: String, token: UUID) {
        guard generation == token, !isShutdown else { return }
        stopMacmon()
        macmonError = message
        let retryToken = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.generation == retryToken, !self.isShutdown else { return }
            self.startMacmon()
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
        isShutdown = true
        auxSub?.cancel()
        auxSub = nil
        watchdogSub?.cancel()
        watchdogSub = nil
        stopMacmon()
    }

    private func restartMacmon() {
        stopMacmon()
        startMacmon()
    }

    // MARK: - History recording

    private func recordHistory(_ m: MacmonOutput) {
        cpuBuf.push(m.cpuPct / 100)
        for tier in m.tiers {
            tierBuffers[tier.label, default: HistoryBuf()].push(tier.activeRatio)
        }
        if gpuAvailable { gpuBuf.push(m.gpuPct / 100) }
        if let temperature = m.temp.cpuTempAvg { cpuTempBuf.push(temperature / 100) }
        if let temperature = m.temp.gpuTempAvg { gpuTempBuf.push(temperature / 100) }
        if powerAvailable {
            cpuPowerBuf.push(m.cpuPower / 30)
            gpuPowerBuf.push(m.gpuPower / 20)
            anePowerBuf.push(m.anePower / 8)
            sysPowerBuf.push(m.sysPower / 65)
        }
        ramBuf.push(m.ramPct / 100)
        swapBuf.push(m.memory.swapTotal > 0 ? Double(m.memory.swapUsage) / Double(m.memory.swapTotal) : 0)
        if hasBattery { batteryBuf.push(batteryLevel / 100) }
        if diskTotalGB > 0 { diskFreeBuf.push(diskFreeGB / diskTotalGB) }

        cpuHistory      = cpuBuf.samples
        cpuTierHistory  = Dictionary(uniqueKeysWithValues: m.tiers.map { ($0.label, tierBuffers[$0.label]?.samples ?? []) })
        gpuHistory      = gpuAvailable ? gpuBuf.samples : []
        cpuTempHistory  = m.temp.cpuTempAvg == nil ? [] : cpuTempBuf.samples
        gpuTempHistory  = m.temp.gpuTempAvg == nil ? [] : gpuTempBuf.samples
        cpuPowerHistory = powerAvailable ? cpuPowerBuf.samples : []
        gpuPowerHistory = powerAvailable ? gpuPowerBuf.samples : []
        anePowerHistory = powerAvailable ? anePowerBuf.samples : []
        sysPowerHistory = powerAvailable ? sysPowerBuf.samples : []
        ramHistory      = ramBuf.samples
        swapHistory     = swapBuf.samples
        batteryHistory  = hasBattery ? batteryBuf.samples : []
        diskFreeHistory = diskTotalGB > 0 ? diskFreeBuf.samples : []
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
