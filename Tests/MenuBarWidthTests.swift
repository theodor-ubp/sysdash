import AppKit

@main
@MainActor
enum MenuBarWidthTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "sysdash.width-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = SystemMonitor(macmonPath: "/nonexistent/width-test", defaults: defaults)
        monitor.shutdown()
        let manager = MenuBarManager()
        manager.settings = MenuBarSettings(showCPU: false, showRAM: true)
        manager.setup(monitor: monitor)
        guard let item = Mirror(reflecting: manager).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem,
              let button = item.button else { fatalError("Missing actual status item") }
        var sample = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        var widths: [CGFloat] = []
        for gigabytes in [9.9, 10.0, 9.9] {
            var memory = sample["memory"] as! [String: Any]
            memory["ram_usage"] = UInt64(gigabytes * 1_073_741_824)
            sample["memory"] = memory
            monitor.macmon = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: sample))
            manager.updateLabel()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            widths.append(button.frame.width)
            print("RAM \(gigabytes): item length \(item.length), frame width \(button.frame.width)")
        }
        fflush(stdout)
        guard item.length > 0, Set(widths).count == 1 else { fatalError("RAM digit change moved the status item's boundaries") }
        print("PASS: actual status item stays fixed through 9.9 → 10.0 → 9.9 GB")

        let legacy = try JSONDecoder().decode(TrayAppearance.self, from: Data(#"{"monospaced":true,"fontSize":14,"characterWidth":85,"characterSpacing":-0.3}"#.utf8))
        precondition(legacy.fixedWidthEnabled && legacy.fixedWidth == 240)
        precondition(legacy.monospaced && legacy.fontSize == 14 && legacy.characterWidth == 85 && legacy.characterSpacing == -0.3)
        var custom = legacy
        custom.fixedWidth = 315; custom.fixedWidthEnabled = false
        let reloaded = try JSONDecoder().decode(TrayAppearance.self, from: JSONEncoder().encode(custom))
        precondition(reloaded == custom)
        custom.fixedWidth = .nan; precondition(custom.normalized.fixedWidth == 240)
        custom.fixedWidth = 0; precondition(custom.normalized.fixedWidth == 80)
        custom.fixedWidth = 9999; precondition(custom.normalized.fixedWidth == 600)
        print("PASS: migration enables fixed width while preserving typography; saved on/off, width and bounds round-trip")

        manager.settings = MenuBarSettings(showCPU: true, showGPU: true, showCPUTemp: true, showGPUTemp: true, showRAM: true, showPower: true, showBattery: true, showNetDown: true, showNetUp: true)
        for monospace in [false, true] {
            manager.settings.appearance.monospaced = monospace
            for width in [80.0, 240, 600] {
                manager.settings.appearance.fixedWidth = width
                for i in 0..<12 {
                    monitor.macmon = i % 4 == 0 ? nil : try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: sample))
                    monitor.isCharging = i % 3 == 0
                    monitor.isOnBattery = i % 3 == 1
                    monitor.hasBattery = i % 4 != 0
                    monitor.networkDownBps = Double(i) * 1_048_576
                    monitor.networkUpBps = Double(i) * 100_000_000
                    manager.updateLabel()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                    let label = manager.currentReadings.label(settings: manager.settings)
                    precondition(item.length == width && button.frame.width == width)
                    precondition(button.image?.size.width == width - MenuBarTypography.itemPadding * 2)
                    precondition(button.attributedTitle.string.isEmpty && button.accessibilityLabel() == label)
                    let natural = MenuBarTypography.text(label, appearance: manager.settings.appearance).size().width
                    let scale = MenuBarTypography.fitScale(label, appearance: manager.settings.appearance)
                    precondition(scale > 0 && scale <= 1 && natural * scale <= width - MenuBarTypography.itemPadding * 2 + 0.001)
                    precondition(button.image?.isTemplate == true)
                    guard let data = button.image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { fatalError("Fixed-width text failed to render") }
                    var visible = false
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide where !visible {
                            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { visible = true }
                        }
                    }
                    precondition(visible, "Fixed-width text rendered blank")
                }
            }
        }
        print("PASS: 72 actual status updates, both fonts, three widths, offline/battery/network changes; rendered text fits and stays accessible")
        let short = "C5%"
        precondition(MenuBarTypography.fitScale(short, appearance: TrayAppearance()) == 1, "Short text must not stretch")
        var crowded = TrayAppearance(); crowded.fontSize = 18; crowded.characterWidth = 150; crowded.characterSpacing = 3; crowded.fixedWidth = 80
        let text = "C100% 100°C G100% 100°C RAM128.0GB PWR999W ⚡100% ↓999.9M ↑999.9M"
        precondition(MenuBarTypography.fitScale(text, appearance: crowded) < 1)
        let height = MenuBarTypography.fixedWidthImage(text, appearance: crowded).size.height
        crowded.fixedWidth = 600
        precondition(MenuBarTypography.fixedWidthImage(text, appearance: crowded).size.height == height, "Horizontal fit must preserve text height")
        for monospace in [false, true] {
            for weight in TrayFontWeight.allCases {
                var largest = TrayAppearance(); largest.fontSize = 18; largest.weight = weight; largest.monospaced = monospace
                let image = MenuBarTypography.fixedWidthImage(text + " 🔋100%", appearance: largest)
                precondition(image.size.height <= button.frame.height, "Largest font/emoji canvas exceeds native status-button height")
            }
        }

        manager.settings = MenuBarSettings(showCPU: false, showRAM: true)
        manager.settings.appearance.fixedWidthEnabled = false
        monitor.macmon = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: sample))
        manager.updateLabel()
        precondition(item.length == NSStatusItem.variableLength && button.image == nil && button.attributedTitle.string == "9.9GB")
        manager.settings.appearance.fixedWidthEnabled = true
        manager.updateLabel()
        precondition(item.length == 240 && button.image != nil)
        print("PASS: overflow compresses horizontally only, short text is not stretched, variable-width opt-out and re-enable work")
    }
}
