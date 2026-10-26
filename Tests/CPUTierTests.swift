import Foundation

@main
enum CPUTierTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func main() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let m6 = try decoder.decode(MacmonOutput.self, from: Data(contentsOf: directory.appendingPathComponent("m6.json")))
        guard m6.soc?.coreLabel == "6E+4P+2S+12GPU" else {
            fputs("FAIL: M6 topology lost a tier: \(m6.soc?.coreLabel ?? "missing")\n", stderr)
            exit(1)
        }
        print("PASS: M6 topology includes all 6 E, 4 P and 2 S cores")
        check(m6.tiers.map(\.label) == ["E", "P", "S"], "All runtime tiers must survive decoding")
        check(m6.tiers.map(\.freqMhz) == [2940, 2394, 4776], "P and S frequencies must remain distinct")
        check(abs(m6.tiers[1].percent - 0.0697166) < 0.00001, "P usage must come from P, not S")
        check(abs(m6.tiers[2].percent - 13.6504245) < 0.00001, "S active residency mapping")
        check(abs(m6.cpuPct - (6 * m6.tiers[0].percent + 4 * m6.tiers[1].percent + 2 * m6.tiers[2].percent) / 12) < 0.00001, "Combined CPU must include all 12 cores")
        print("PASS: three-tier frequencies, active residency and combined core-weighted CPU")

        for (file, labels, summary) in [
            ("m5", ["E", "S"], "6E+4S+10GPU"),
            ("m5-pro", ["P", "S"], "10P+5S+16GPU"),
            ("vm", ["_"], "4 cores")
        ] {
            let decoded = try decoder.decode(MacmonOutput.self, from: Data(contentsOf: directory.appendingPathComponent(file + ".json")))
            check(decoded.soc?.cpuTiers.map(\.label) == labels, "\(file) must not invent another core type")
            check(decoded.tiers.map(\.label) == labels && decoded.soc?.coreLabel == summary, "\(file) topology")
            if file == "vm" {
                check(decoded.soc?.vm == true && decoded.soc?.cpuTiers[0].maxMHz == nil, "VM must have no fabricated frequency ceiling")
                check(decoded.soc?.gpuMaxMHz == nil && formatFrequency(decoded.tiers[0].freqMhz) == "—", "VM frequency availability")
            }
        }
        print("PASS: M5 E/S, M5 Pro P/S and single-tier VM compatibility")

        var canonical = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("m6.json"))) as! [String: Any]
        var soc = canonical["soc"] as! [String: Any]
        for key in Array(soc.keys) where key.hasPrefix("ecpu_") || key.hasPrefix("pcpu_") { soc.removeValue(forKey: key) }
        canonical["soc"] = soc
        for key in Array(canonical.keys) where key.hasPrefix("ecpu_") || key.hasPrefix("pcpu_") { canonical.removeValue(forKey: key) }
        let onlyTiers = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: canonical))
        check(onlyTiers.soc?.coreLabel == m6.soc?.coreLabel && onlyTiers.tiers.count == 3, "New schema must not depend on deprecated fields")
        soc.removeValue(forKey: "cpu_tiers")
        soc["ecpu_cores"] = 6; soc["pcpu_cores"] = 4
        soc["ecpu_label"] = "E"; soc["pcpu_label"] = "P"
        soc["ecpu_freqs"] = [900, 2808, 1080]; soc["pcpu_freqs"] = [912, 4464, 1260]
        canonical["soc"] = soc; canonical.removeValue(forKey: "cpu_tiers")
        canonical["ecpu_freq_mhz"] = 1200; canonical["pcpu_freq_mhz"] = 2400
        canonical["ecpu_active_ratio"] = 0.2; canonical["pcpu_active_ratio"] = 0.6
        let legacy = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: canonical))
        check(legacy.soc?.coreLabel == "6E+4P+12GPU" && legacy.tiers.map(\.freqMhz) == [1200, 2400], "0.9 fallback")
        check(legacy.soc?.cpuTiers.map(\.maxMHz) == [2808, 4464], "Unsorted frequency tables use actual maxima")
        print("PASS: canonical-only JSON and legacy 0.9 fallback; unsorted frequency tables")

        var invalid = try JSONSerialization.jsonObject(with: m6Data(directory)) as! [String: Any]
        var tiers = invalid["cpu_tiers"] as! [[String: Any]]
        tiers[1]["label"] = "E"
        invalid["cpu_tiers"] = tiers
        let duplicate = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: invalid))
        do {
            try duplicate.validateTiers()
            fatalError("Duplicate tiers must be rejected before reaching charts")
        } catch is DecodingError {}
        print("PASS: duplicate tier labels rejected before publishing readings")
    }

    static func m6Data(_ directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("m6.json"))
    }
}
