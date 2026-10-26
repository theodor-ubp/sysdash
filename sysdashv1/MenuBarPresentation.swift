import AppKit
import CoreText

// Shared by the real tray button and the settings preview.
enum MenuBarTypography {
    static func font(appearance: TrayAppearance) -> NSFont {
        let style = appearance.normalized
        let base = style.monospaced
            ? NSFont.monospacedSystemFont(ofSize: style.fontSize, weight: style.weight.fontWeight)
            : NSFont.systemFont(ofSize: style.fontSize, weight: style.weight.fontWeight)
        guard style.characterWidth != 100 else { return base }
        var matrix = CGAffineTransform(scaleX: style.characterWidth / 100, y: 1)
        return CTFontCreateCopyWithAttributes(base as CTFont, style.fontSize, &matrix, nil) as NSFont
    }

    static func text(_ value: String, appearance: TrayAppearance) -> NSAttributedString {
        let style = appearance.normalized
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(appearance: style), .foregroundColor: NSColor.labelColor
        ]
        if style.monospaced { attributes[.ligature] = 0 }
        if style.characterSpacing != 0 { attributes[.kern] = style.characterSpacing }
        return NSAttributedString(string: value, attributes: attributes)
    }
}

struct MenuBarReadings {
    var cpuPercent: Double?
    var gpuPercent: Double?
    var cpuTemperature: Double?
    var gpuTemperature: Double?
    var ramGB: Double?
    var systemWatts: Double?
    var batteryPercent: Double?
    var isCharging = false
    var isOnBattery = false
    var downloadBps: Double?
    var uploadBps: Double?

    static let preview = MenuBarReadings(cpuPercent: 5, gpuPercent: 10, cpuTemperature: 35,
        gpuTemperature: 25, ramGB: 9, systemWatts: 6, batteryPercent: 60,
        downloadBps: 13 * 1024, uploadBps: 10 * 1024)

    func label(settings: MenuBarSettings) -> String {
        let style = settings.appearance.normalized
        let gap = String(repeating: " ", count: style.valueSpacing)
        var parts: [String] = []
        func processor(_ name: String, usage: Double?, temperature: Double?, showUsage: Bool, showTemperature: Bool) {
            guard showUsage || showTemperature else { return }
            var values: [String] = []
            if showUsage { values.append(usage.map { String(format: "%.0f%%", $0) } ?? "—") }
            if showTemperature { values.append(formatTemperature(temperature, suffix: style.temperatureUnit.rawValue)) }
            parts.append(name + String(repeating: " ", count: style.processorLabelSpacing) + values.joined(separator: gap))
        }
        processor(style.fullProcessorLabels ? "CPU" : "C", usage: cpuPercent, temperature: cpuTemperature,
                  showUsage: settings.showCPU, showTemperature: settings.showCPUTemp)
        processor(style.fullProcessorLabels ? "GPU" : "G", usage: gpuPercent, temperature: gpuTemperature,
                  showUsage: settings.showGPU, showTemperature: settings.showGPUTemp)
        func system(_ name: String, _ value: String) {
            parts.append(style.systemLabels ? name + gap + value : value)
        }
        if settings.showRAM { system("RAM", ramGB.map { String(format: "%.1fGB", $0) } ?? "—") }
        if settings.showPower { system("PWR", systemWatts.map { String(format: "%.0fW", $0) } ?? "—") }
        if settings.showBattery {
            let value = batteryPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            if batteryPercent == nil {
                parts.append("Battery" + gap + value)
            } else {
                let symbols = style.batterySymbols && !style.monospaced
                let state = isCharging ? (symbols ? "⚡" : "CHG") : (isOnBattery ? (symbols ? "🔋" : "BAT") : "")
                let battery = state.isEmpty ? value : state + (symbols ? "" : gap) + value
                if style.systemLabels && state == "BAT" { parts.append(battery) }
                else { system("BAT", battery) }
            }
        }
        if settings.showNetDown { parts.append(Self.rate(downloadBps, prefix: "↓")) }
        if settings.showNetUp { parts.append(Self.rate(uploadBps, prefix: "↑")) }
        return parts.isEmpty ? "UP Sysdash" : parts.joined(separator: settings.separator.text(spacing: style.groupSpacing))
    }

    private static func rate(_ reading: Double?, prefix: String) -> String {
        guard let bps = reading, bps.isFinite, bps >= 0 else { return prefix + "—" }
        if bps >= 1_048_576 { return String(format: "%@%.1fM", prefix, bps / 1_048_576) }
        if bps >= 1024 { return String(format: "%@%.0fK", prefix, bps / 1024) }
        return String(format: "%@%.0fB", prefix, bps)
    }
}
