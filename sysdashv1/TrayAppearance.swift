import AppKit

enum TrayFontWeight: String, Codable, CaseIterable {
    case regular, medium, semibold
    var title: String { rawValue.capitalized }
    var fontWeight: NSFont.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        }
    }
}

enum TrayTemperatureUnit: String, Codable, CaseIterable {
    case text = "deg"
    case symbol = "°"
    case celsius = "°C"
}

struct TrayAppearance: Codable, Equatable {
    var monospaced = false
    var fontSize = Double(NSFont.systemFontSize)
    var weight = TrayFontWeight.regular
    var characterWidth = 100.0
    var characterSpacing = 0.0
    var processorLabelSpacing = 0
    var valueSpacing = 1
    var groupSpacing = 1
    var temperatureUnit = TrayTemperatureUnit.symbol
    var fullProcessorLabels = false
    var systemLabels = false
    var batterySymbols = true

    var normalized: Self {
        var result = self
        result.fontSize = fontSize.isFinite ? min(max(fontSize, 9), 18) : Double(NSFont.systemFontSize)
        result.characterWidth = characterWidth.isFinite ? min(max(characterWidth, 50), 150) : 100
        result.characterSpacing = characterSpacing.isFinite ? min(max(characterSpacing, -1), 3) : 0
        result.processorLabelSpacing = min(max(processorLabelSpacing, 0), 3)
        result.valueSpacing = min(max(valueSpacing, 0), 3)
        result.groupSpacing = min(max(groupSpacing, 0), 4)
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case monospaced, fontSize, weight, characterWidth, characterSpacing
        case processorLabelSpacing, valueSpacing, groupSpacing, temperatureUnit, fullProcessorLabels, systemLabels, batterySymbols
    }
}

extension TrayAppearance {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monospaced = (try? c.decode(Bool.self, forKey: .monospaced)) ?? monospaced
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? fontSize
        weight = (try? c.decode(TrayFontWeight.self, forKey: .weight)) ?? weight
        characterWidth = (try? c.decode(Double.self, forKey: .characterWidth)) ?? characterWidth
        characterSpacing = (try? c.decode(Double.self, forKey: .characterSpacing)) ?? characterSpacing
        processorLabelSpacing = (try? c.decode(Int.self, forKey: .processorLabelSpacing)) ?? processorLabelSpacing
        valueSpacing = (try? c.decode(Int.self, forKey: .valueSpacing)) ?? valueSpacing
        groupSpacing = (try? c.decode(Int.self, forKey: .groupSpacing)) ?? groupSpacing
        temperatureUnit = (try? c.decode(TrayTemperatureUnit.self, forKey: .temperatureUnit)) ?? temperatureUnit
        fullProcessorLabels = (try? c.decode(Bool.self, forKey: .fullProcessorLabels)) ?? fullProcessorLabels
        systemLabels = (try? c.decode(Bool.self, forKey: .systemLabels)) ?? systemLabels
        batterySymbols = (try? c.decode(Bool.self, forKey: .batterySymbols)) ?? batterySymbols
        self = normalized
    }
}
