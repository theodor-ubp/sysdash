import AppKit
import CoreText

// Shared by the real tray button and the settings preview.
enum MenuBarTypography {
    static let itemPadding: CGFloat = 6

    static func fitScale(_ value: String, appearance: TrayAppearance) -> CGFloat {
        let style = appearance.normalized
        let naturalWidth = text(value, appearance: style).size().width
        return naturalWidth > 0 ? min(1, (style.fixedWidth - itemPadding * 2) / naturalWidth) : 1
    }

    // Render the complete run, including fallback glyphs and spacing, into a
    // fixed canvas. Scaling only X keeps the selected font's height unchanged.
    static func fixedWidthImage(_ value: String, appearance: TrayAppearance) -> NSImage {
        let style = appearance.normalized
        let attributed = NSMutableAttributedString(attributedString: text(value, appearance: style))
        attributed.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: attributed.length))
        let size = NSSize(width: style.fixedWidth - itemPadding * 2, height: max(18, ceil(attributed.size().height) + 1))
        let scale = fitScale(value, appearance: style)
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            defer { context.restoreGState() }
            context.clip(to: bounds)
            context.translateBy(x: 0, y: (bounds.height - attributed.size().height) / 2)
            context.scaleBy(x: scale, y: 1)
            attributed.draw(at: .zero)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = value
        return image
    }

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
