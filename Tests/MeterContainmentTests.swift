import AppKit
import SwiftUI

@main
@MainActor
enum MeterContainmentTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "sysdash.card-charts-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = CardChartSettings.load(defaults: defaults)
        guard settings.style(for: "cpu") == .line, settings.style(for: "cpu-tier-S") == .line else { fatalError("Changed default charts") }
        settings.setStyle(.segments, for: "cpu-tier-S")
        settings.setStyle(.area, for: "ram")
        settings.save(defaults: defaults)
        guard CardChartSettings.load(defaults: defaults) == settings, settings.style(for: "cpu") == .line,
              settings.style(for: "cpu-tier-S") == .segments else { fatalError("Card styles did not persist independently") }
        settings.applyToAll(.bar)
        guard settings.overrides.isEmpty, settings.style(for: "cpu-tier-S") == .bar, settings.style(for: "future-card") == .bar else { fatalError("Apply all did not include future tiers") }
        let compatible = try JSONDecoder().decode(CardChartSettings.self, from: Data(#"{"defaultStyle":"future","overrides":{"ram":"area","cpu":"future","cpu-tier-S":"none"}}"#.utf8))
        guard compatible.defaultStyle == .line, compatible.style(for: "ram") == .area, compatible.style(for: "cpu") == .line,
              compatible.style(for: "cpu-tier-S") == .none else { fatalError("Unknown styles lost compatible settings") }
        print("PASS: default charts, per-card and S-core persistence, apply-all behavior and unknown-style migration")
        var barCounts: [CardChartStyle: [Int]] = [:]
        for style in CardChartStyle.allCases {
            for available in [false, true] {
                for progress in [-1.0, 0, 0.5, 1, 2, .nan, .infinity] {
                    for width in [70.0, 100.0, 220.0] {
                        let chart = CardChart(style: style, history: [0, 1, .nan, .infinity, 0.5, 1], progress: progress, tint: .cyan, available: available)
                            .frame(width: width, height: 24).padding(10).background(Color.black)
                        let renderer = ImageRenderer(content: chart)
                        renderer.scale = 2
                        guard let image = renderer.cgImage else { fatalError("Cannot render chart style") }
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        var litPixels = 0
                        var filledPixels = 0
                        for y in 0..<bitmap.pixelsHigh {
                            for x in 0..<bitmap.pixelsWide {
                                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                                let lit = color.redComponent + color.greenComponent + color.blueComponent > 0.02
                                if lit { litPixels += 1 }
                                if color.greenComponent > 0.3 { filledPixels += 1 }
                                if x < 20 || x >= Int(width * 2) + 20 || y < 20 || y >= 68 {
                                    guard !lit else { fatalError("Chart \(style) escaped bounds at \(width), \(progress)") }
                                }
                            }
                        }
                        if !available || style == .none {
                            guard litPixels == 0 else { fatalError("Unavailable/value-only chart displayed a false meter") }
                        } else {
                            guard litPixels > 0 else { fatalError("Chart style is blank") }
                            if width == 100, [0.0, 0.5, 1.0].contains(progress), style == .bar || style == .segments {
                                barCounts[style, default: []].append(filledPixels)
                            }
                        }
                    }
                }
            }
        }
        for style in [CardChartStyle.bar, .segments] {
            let counts = barCounts[style] ?? []
            guard counts.count == 3, counts[0] == 0, counts[1] > 0, counts[2] > counts[1] else { fatalError("\(style) level does not match 0/50/100%") }
        }
        print("PASS: all five styles at three widths; accurate bar levels, bounded invalid input, unavailable/value-only charts remain blank")
        for values in [[1.0, 0, 1], [0.0, 1, 0], [-5.0, 4, 0.5], [Double.nan, .infinity, 1]] {
            for width in [70.0, 100.0, 220.0] {
                let chart = Sparkline(data: values, tint: .cyan)
                    .frame(width: width, height: 24)
                    .padding(10)
                    .background(Color.black)
                let renderer = ImageRenderer(content: chart)
                renderer.scale = 2
                guard let image = renderer.cgImage else { fatalError("Cannot render meter") }
                let bitmap = NSBitmapImageRep(cgImage: image)
                var escaped = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard x < 20 || x >= Int(width * 2) + 20 || y < 20 || y >= 68 else { continue }
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.redComponent + color.greenComponent + color.blueComponent > 0.02 { escaped += 1 }
                    }
                }
                guard escaped == 0 else {
                    fputs("FAIL: \(escaped) painted pixels escaped the chart bounds at width \(width)\n", stderr)
                    exit(1)
                }
            }
        }
        print("PASS: sparkline fill, stroke and endpoint stay inside chart bounds at 0/100%, invalid values and three widths")
        for style in CardChartStyle.allCases {
          for progress in [-1.0, 0, 0.5, 1, 2, .nan, .infinity] {
            let card = MetricCard(label: "TEST", value: "100%", detail: nil, progress: progress, tint: .cyan, history: [0, 0.5, 1], chartStyle: style)
                .environment(\.colorScheme, .dark)
                .frame(width: 120, height: 120)
                .padding(10)
                .background(Color.black)
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Cannot render progress card") }
            let bitmap = NSBitmapImageRep(cgImage: image)
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard x < 20 || x >= 260 || y < 20 || y >= 260 else { continue }
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    guard color.redComponent + color.greenComponent + color.blueComponent <= 0.02 else {
                        fatalError("Progress card painted outside its bounds for input \(progress)")
                    }
                }
            }
          }
        }
        print("PASS: progress cards stay inside their bounds at 0/50/100%, out-of-range and non-finite input")
    }
}
