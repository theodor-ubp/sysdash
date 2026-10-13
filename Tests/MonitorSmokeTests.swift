import Foundation
import Combine
import Darwin

@main
enum MonitorSmokeTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func wait(_ seconds: Double, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        check(condition(), "Timed out after \(seconds) seconds")
    }

    static func children(_ path: String) throws -> [Int32] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid,ppid,command"]
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self).split(separator: "\n").compactMap { line in
            let columns = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard columns.count == 3, Int32(columns[1]) == getpid(), columns[2].contains(path) else { return nil }
            return Int32(columns[0])
        }
    }

    static func main() throws {
        let binary = CommandLine.arguments[1]
        let suite = "sysdash.smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sample = """
        {"temp":{"cpu_temp_avg":null,"gpu_temp_avg":43.5},
         "memory":{"ram_total":17179869184,"ram_usage":8589934592,"swap_total":0,"swap_usage":0},
         "ecpu_freq_mhz":1200,"pcpu_freq_mhz":2400,"gpu_freq_mhz":338,
         "ecpu_active_ratio":0.5,"pcpu_active_ratio":0.25,"cpu_active_ratio":0.4,"gpu_active_ratio":0.75,
         "cpu_scaled_ratio":0.2,"gpu_scaled_ratio":0.1,
         "cpu_power":3.0,"gpu_power":2.0,"ane_power":0.5,"all_power":5.5,
         "sys_power":8.0,"ram_power":0.0,"gpu_ram_power":0.0}
        """.replacingOccurrences(of: "\n", with: "")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let metrics = try decoder.decode(MacmonOutput.self, from: Data(sample.utf8))
        check(metrics.temp.cpuTempAvg == nil, "Null CPU temperature must remain unavailable")
        check(formatTemperature(nil) == "—", "Unavailable temperature formatting")
        check(formatTemperature(43.5, suffix: " °C") == "44 °C", "Temperature formatting")
        check(metrics.cpuPct == 40 && metrics.gpuPct == 75, "Usage must represent active residency")
        check(metrics.ecpuPct == 50 && metrics.pcpuPct == 25, "Cluster usage mapping")
        check(metrics.ecpuFreqMHz == 1200 && metrics.pcpuFreqMHz == 2400, "Frequency mapping")
        check(metrics.ramUsedGB == 8 && metrics.ramTotalGB == 16 && metrics.ramPct == 50, "Memory units")
        print("PASS: canonical JSON, nullable temperatures, usage, frequency, memory units")

        // Exercise fragmented lines and a decode failure using the actual reader.
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("sysdash-fixture-\(UUID().uuidString)")
        let fixtureScript = """
        #!/usr/bin/python3
        import os, time
        line = \(String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)).encode()
        os.write(1, b'{invalid}\\n')
        time.sleep(0.5)
        os.write(1, line[:35])
        time.sleep(0.05)
        os.write(1, line[35:] + b'\\n')
        time.sleep(60)
        """
        try fixtureScript.write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.path)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let fixtureMonitor = SystemMonitor(macmonPath: fixture.path, defaults: defaults)
        wait(10) { fixtureMonitor.macmonError?.contains("Cannot read") == true }
        check(!fixtureMonitor.macmonRunning && fixtureMonitor.macmon == nil, "Bad JSON must mark the monitor offline")
        wait(5) { fixtureMonitor.macmonRunning }
        check(fixtureMonitor.cpuHistory == [0.4], "Fragmented line must produce exactly one sample")
        check(fixtureMonitor.cpuTempHistory.isEmpty, "Unavailable temperature must not create a zero history sample")
        check(fixtureMonitor.gpuTempHistory == [0.435], "Valid temperature history")
        fixtureMonitor.shutdown()
        wait(5) { (try? children(fixture.path).isEmpty) == true }
        print("PASS: fragmented JSON stream, visible decode errors, recovery, unavailable temperature history")

        let monitor = SystemMonitor(macmonPath: binary, defaults: defaults)
        defer { monitor.shutdown() }
        wait(10) { monitor.macmonRunning && monitor.cpuHistory.count >= 3 }
        let live = monitor.macmon!
        check(live.memory.ramTotal == ProcessInfo.processInfo.physicalMemory, "Physical RAM mismatch")
        check(live.memory.ramUsage <= live.memory.ramTotal, "RAM usage exceeds installed memory")
        check(live.cpuPct >= 0 && live.cpuPct <= 100 && live.gpuPct >= 0 && live.gpuPct <= 100, "Invalid utilization")
        check(live.cpuPower > 0 && live.sysPower >= live.allPower, "macOS 27 power counters unavailable")
        check(abs(live.allPower - live.cpuPower - live.gpuPower - live.anePower) < 0.01, "Chip power must equal CPU + GPU + ANE")
        check(monitor.diskFreeGB > 0 && monitor.diskTotalGB > monitor.diskFreeGB, "Invalid disk reading")
        check(monitor.batteryLevel >= 0 && monitor.batteryLevel <= 100, "Invalid battery reading")
        check(monitor.networkUpBps.isFinite && monitor.networkDownBps.isFinite, "Invalid network reading")
        print("PASS: live \(live.soc?.chipName ?? "unknown") / \(live.soc?.coreLabel ?? "unknown") / \(live.ramTotalGB) GB; CPU \(live.cpuPower) W")

        for interval in [500, 2000, 5000, 1000] {
            let before = monitor.cpuHistory.count
            monitor.intervalMs = interval
            check(!monitor.macmonRunning && monitor.macmon == nil, "Restart must clear stale metrics")
            wait(Double(interval) / 1000 + 8) { monitor.macmonRunning && monitor.cpuHistory.count > before }
            wait(5) { (try? children(binary).count) == 1 }
        }
        // Multiple changes before the main queue runs must leave one helper.
        monitor.intervalMs = 5000
        monitor.intervalMs = 2000
        monitor.intervalMs = 500
        wait(10) { monitor.macmonRunning }
        wait(5) { (try? children(binary).count) == 1 }
        print("PASS: all four refresh intervals and rapid interval changes")

        let oldPID = try children(binary).first!
        kill(oldPID, SIGKILL)
        wait(5) { !monitor.macmonRunning && monitor.macmonError != nil }
        check(monitor.macmon == nil, "Helper failure must clear stale metrics")
        check(monitor.socInfo == live.soc, "Static hardware info must survive a helper restart")
        wait(10) { monitor.macmonRunning }
        let restartedPID = try children(binary).first
        check(restartedPID != oldPID, "Helper was not restarted")
        print("PASS: unexpected helper termination and automatic restart")
        monitor.shutdown()
        wait(5) { (try? children(binary).isEmpty) == true }
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        let remainingChildren = try children(binary)
        check(remainingChildren.isEmpty, "Shutdown must cancel pending restart")
        check(!monitor.macmonRunning && monitor.macmon == nil, "Shutdown state")
        print("PASS: clean shutdown without orphan helpers")
    }
}
