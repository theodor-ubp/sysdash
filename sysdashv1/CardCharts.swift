import SwiftUI

enum CardChartStyle: String, Codable, CaseIterable, Identifiable {
    case line, area, bar, segments, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .line: return "Line graph"
        case .area: return "Area graph"
        case .bar: return "Level bar"
        case .segments: return "Segmented bar"
        case .none: return "Value only"
        }
    }
}

struct CardChartSettings: Codable, Equatable {
    var defaultStyle = CardChartStyle.line
    var overrides: [String: CardChartStyle] = [:]

    func style(for card: String) -> CardChartStyle { overrides[card] ?? defaultStyle }

    mutating func setStyle(_ style: CardChartStyle, for card: String) {
        overrides[card] = style == defaultStyle ? nil : style
    }

    mutating func applyToAll(_ style: CardChartStyle) {
        defaultStyle = style
        overrides.removeAll()
    }

    private enum CodingKeys: String, CodingKey { case defaultStyle, overrides }

    static func load(defaults: UserDefaults = .standard) -> CardChartSettings {
        guard let data = defaults.data(forKey: "sysdash.cardCharts"),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "sysdash.cardCharts") }
    }
}

extension CardChartSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultStyle = (try? container.decode(CardChartStyle.self, forKey: .defaultStyle)) ?? .line
        let raw = (try? container.decode([String: String].self, forKey: .overrides)) ?? [:]
        overrides = raw.compactMapValues(CardChartStyle.init(rawValue:))
    }
}

struct CardChart: View {
    let style: CardChartStyle
    let history: [Double]
    let progress: Double
    let tint: Color
    var available = true

    var body: some View {
        Group {
            if available {
                switch style {
                case .line, .area:
                    Sparkline(data: history, tint: tint, area: style == .area)
                case .bar, .segments:
                    Canvas { context, size in
                        let inset: CGFloat = 3
                        let width = max(0, size.width - inset * 2)
                        let level = progress.isFinite ? min(max(progress, 0), 1) : 0
                        let count = style == .segments ? 10 : 1
                        let gap: CGFloat = style == .segments ? 3 : 0
                        let segmentWidth = max(0, (width - CGFloat(count - 1) * gap) / CGFloat(count))
                        let height = min(8, max(0, size.height - inset * 2))
                        guard segmentWidth > 0, height > 0 else { return }
                        for index in 0..<count {
                            let rect = CGRect(x: inset + CGFloat(index) * (segmentWidth + gap), y: (size.height - height) / 2, width: segmentWidth, height: height)
                            let track = Path(roundedRect: rect, cornerRadius: style == .bar ? height / 2 : 2)
                            context.fill(track, with: .color(tint.opacity(0.15)))
                            let fraction = min(max(level * Double(count) - Double(index), 0), 1)
                            if fraction > 0 {
                                var foreground = context
                                foreground.clip(to: track)
                                foreground.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: segmentWidth * fraction, height: height)), with: .color(tint))
                            }
                        }
                    }
                case .none:
                    Color.clear
                }
            } else {
                Color.clear
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
