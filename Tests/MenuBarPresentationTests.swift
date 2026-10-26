import AppKit
import CoreText

@main
@MainActor
enum MenuBarPresentationTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
    static func width(_ text: NSAttributedString) -> Double {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(text), nil, nil, nil)
    }
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let readings = MenuBarReadings.preview
        var all = MenuBarSettings(showCPU: true, showGPU: true, showCPUTemp: true,
            showGPUTemp: true, showRAM: true, showPower: true, showBattery: true,
            showNetDown: true, showNetUp: true, separator: .none)
        let expected = "C5% 35° G10% 25° 9.0GB 6W 60% ↓13K ↑10K"
        check(readings.label(settings: all) == expected, "Requested default tray format")
        let initial = TrayAppearance()
        let font = MenuBarTypography.font(appearance: initial)
        check(!initial.monospaced && font.pointSize == NSFont.systemFontSize, "System font default")
        check(initial.characterWidth == 100 && initial.characterSpacing == 0 && initial.weight == .regular, "Natural typography defaults")
        check(!font.isFixedPitch, "Default font must be proportional")
        check(MenuBarTypography.text(expected, appearance: initial).attribute(.kern, at: 0, effectiveRange: nil) == nil, "Default must not force kerning")
        print("PASS: original normal system font and exact C/G format; no forced width or spacing")

        for bits in 0..<512 {
            let s = MenuBarSettings(showCPU: bits & 1 != 0, showGPU: bits & 2 != 0,
                showCPUTemp: bits & 4 != 0, showGPUTemp: bits & 8 != 0,
                showRAM: bits & 16 != 0, showPower: bits & 32 != 0,
                showBattery: bits & 64 != 0, showNetDown: bits & 128 != 0,
                showNetUp: bits & 256 != 0, separator: .none)
            let text = readings.label(settings: s)
            check((text.hasPrefix("C") || text.contains(" C")) == (s.showCPU || s.showCPUTemp), "CPU selection")
            check((text.hasPrefix("G") || text.contains(" G")) == (s.showGPU || s.showGPUTemp), "GPU selection")
            check(text.contains("35°") == s.showCPUTemp && text.contains("25°") == s.showGPUTemp, "Temperature selection")
            check(text.contains("9.0GB") == s.showRAM && text.contains("6W") == s.showPower && text.contains("60%") == s.showBattery, "System selection")
            check(text.contains("↓") == s.showNetDown && text.contains("↑") == s.showNetUp, "Network direction")
            if bits == 0 { check(text == "UP Sysdash", "Empty selection fallback") }
        }
        var temp = MenuBarSettings(); temp.showCPU = false; temp.showCPUTemp = true
        check(readings.label(settings: temp) == "C35°", "CPU temperature label")
        temp.showCPUTemp = false; temp.showGPUTemp = true
        check(readings.label(settings: temp) == "G25°", "GPU temperature label")
        check(MenuBarReadings().label(settings: all) == "C— — G— — — — Battery — ↓— ↑—", "Unavailable fields")
        var charging = readings; charging.isCharging = true
        check(charging.label(settings: all).contains("⚡60%"), "Initial battery symbols")
        var rate = readings; rate.downloadBps = 1_048_576
        check(rate.label(settings: all).contains("↓1.0M"), "Initial network precision")
        rate.downloadBps = .nan
        check(rate.label(settings: all).contains("↓—"), "Invalid network reading must be unavailable")
        print("PASS: 512 metric combinations, temperature-only labels, unavailable readings and original system formats")

        let legacy = Data(#"{"showCPU":false,"showGPU":true,"showCPUTemp":true,"showRAM":true,"separator":" | "}"#.utf8)
        let old = try JSONDecoder().decode(MenuBarSettings.self, from: legacy)
        check(!old.showCPU && old.showGPU && old.showCPUTemp && old.showRAM && old.separator == .pipe, "Legacy flags and separator must survive")
        check(old.appearance == TrayAppearance(), "Legacy settings get normal appearance defaults")
        let partial = try JSONDecoder().decode(TrayAppearance.self, from: Data(#"{"monospaced":true,"fontSize":14,"characterWidth":125}"#.utf8))
        check(partial.monospaced && partial.fontSize == 14 && partial.characterWidth == 125 && partial.characterSpacing == 0, "Partial appearance migration")
        var custom = partial
        custom.characterSpacing = 0.5; custom.processorLabelSpacing = 2; custom.valueSpacing = 0; custom.groupSpacing = 2
        custom.temperatureUnit = .symbol; custom.fullProcessorLabels = true; custom.systemLabels = true
        all.appearance = custom
        let saved = try JSONEncoder().encode(all)
        let loaded = try JSONDecoder().decode(MenuBarSettings.self, from: saved)
        check(loaded == all, "All appearance and metric preferences must persist")
        all.appearance = TrayAppearance()
        check(all.showGPU && all.showNetUp && all.separator == .none, "Reset appearance must not change readings or separator")
        var invalid = TrayAppearance(); invalid.fontSize = .nan; invalid.characterWidth = -999
        invalid.characterSpacing = .infinity; invalid.valueSpacing = -9; invalid.groupSpacing = 999
        let safe = invalid.normalized
        check(safe.fontSize == Double(NSFont.systemFontSize) && safe.characterWidth == 50 && safe.characterSpacing == 0 && safe.valueSpacing == 0 && safe.groupSpacing == 4, "Safe numeric bounds")
        print("PASS: legacy/partial migration, all preference persistence, reset isolation and safe bounds")

        var mono = TrayAppearance(); mono.monospaced = true
        let cell = width(MenuBarTypography.text("0", appearance: mono))
        for character in Set((expected + "UP Sysdash—CHG+BAT").map(String.init)) {
            check(abs(width(MenuBarTypography.text(character, appearance: mono)) - cell) < 0.001, "Optional monospace character advance")
        }
        let normalWidth = width(MenuBarTypography.text(expected, appearance: initial))
        var narrow = initial; narrow.characterWidth = 80
        check(width(MenuBarTypography.text(expected, appearance: narrow)) < normalWidth, "Width control")
        narrow.characterSpacing = 1
        check(width(MenuBarTypography.text(expected, appearance: narrow)) > width(MenuBarTypography.text(expected, appearance: { var a = initial; a.characterWidth = 80; return a }())), "Tracking control")
        var onBattery = readings; onBattery.isOnBattery = true
        all.appearance = mono; all.appearance.systemLabels = true
        check(!onBattery.label(settings: all).contains("BAT BAT"), "No duplicate battery labels")
        print("PASS: optional monospace, width/spacing controls and battery label composition")
    }
}
