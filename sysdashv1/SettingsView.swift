import SwiftUI
import AppKit

private final class MenuBarPreviewContent: NSView {
    let label = NSTextField(labelWithString: "")
    let imageView = NSImageView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byClipping
        label.usesSingleLineMode = true
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignLeft
        imageView.contentTintColor = .labelColor
        addSubview(label)
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private struct MenuBarPreviewLabel: NSViewRepresentable {
    let text: String
    let appearance: TrayAppearance
    func makeNSView(context: Context) -> MenuBarPreviewContent {
        MenuBarPreviewContent(frame: .zero)
    }
    func updateNSView(_ view: MenuBarPreviewContent, context: Context) {
        let style = appearance.normalized
        view.label.isHidden = style.fixedWidthEnabled
        view.imageView.isHidden = !style.fixedWidthEnabled
        if style.fixedWidthEnabled {
            let image = MenuBarTypography.fixedWidthImage(text, appearance: style)
            view.imageView.image = image
            view.imageView.frame = NSRect(x: MenuBarTypography.itemPadding, y: (30 - image.size.height) / 2, width: image.size.width, height: image.size.height)
            view.imageView.setAccessibilityLabel(text)
        } else {
            view.label.attributedStringValue = MenuBarTypography.text(text, appearance: style)
            view.label.sizeToFit()
            view.label.frame.origin = NSPoint(x: 0, y: (30 - view.label.frame.height) / 2)
        }
        view.toolTip = text
    }
}

struct SettingsView: View {
    @ObservedObject var menuBar: MenuBarManager
    @ObservedObject var monitor: SystemMonitor
    @State private var page = Page.readings
    @State private var livePreview = false
    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var launchError: String?

    private enum Page: String, CaseIterable {
        case readings = "Readings", appearance = "Text & spacing", cards = "Cards", general = "General"
        var icon: String {
            switch self {
            case .readings: return "chart.bar"
            case .appearance: return "textformat"
            case .cards: return "chart.xyaxis.line"
            case .general: return "gearshape"
            }
        }
        var subtitle: String {
            switch self {
            case .readings: return "Choose the information shown in your menu bar."
            case .appearance: return "Set the font, width and spacing to suit your screen."
            case .cards: return "Choose a chart or bar for each dashboard card."
            case .general: return "Refresh, startup and monitoring."
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SysDash").font(.title3.bold()).padding(.horizontal, 10).padding(.bottom, 16)
                ForEach(Page.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 12, weight: page == item ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                            .background(page == item ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text("Changes apply immediately")
                    .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10)
            }
            .padding(12).frame(width: 168)
            .background(Color.primary.opacity(0.025))
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.rawValue).font(.title2.bold())
                    Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch page {
                        case .readings: readingsPage
                        case .appearance: appearancePage
                        case .cards: cardsPage
                        case .general: generalPage
                        }
                    }
                    .padding(.bottom, 2)
                }
                .id(page)
                preview
            }
            .padding(20)
        }
        .frame(width: 720, height: 600)
        .onChange(of: menuBar.settings) { _ in menuBar.saveSettings() }
        .onChange(of: menuBar.cardCharts) { $0.save() }
    }

    private var readingsPage: some View {
        VStack(spacing: 12) {
            card("Processors") {
                processorRow("CPU", usage: $menuBar.settings.showCPU, temperature: $menuBar.settings.showCPUTemp)
                Divider()
                processorRow("GPU", usage: $menuBar.settings.showGPU, temperature: $menuBar.settings.showGPUTemp)
            }
            card("System") {
                Toggle("RAM used", isOn: $menuBar.settings.showRAM)
                Toggle("System power", isOn: $menuBar.settings.showPower)
                Toggle("Battery", isOn: $menuBar.settings.showBattery)
            }
            card("Network") {
                Toggle("Download speed", isOn: $menuBar.settings.showNetDown)
                Toggle("Upload speed", isOn: $menuBar.settings.showNetUp)
            }
        }
    }

    private var appearancePage: some View {
        VStack(spacing: 12) {
            card("Menu bar width") {
                Toggle("Fixed width for all stats", isOn: $menuBar.settings.appearance.fixedWidthEnabled)
                adjustment("Item width", value: $menuBar.settings.appearance.fixedWidth, range: 80...600, step: 5, display: String(format: "%.0f pt", menuBar.settings.appearance.fixedWidth))
                    .disabled(!menuBar.settings.appearance.fixedWidthEnabled)
                Text("Keeps neighboring menu bar icons still. Text compresses horizontally when needed to fit the chosen width.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            card("Font") {
                Toggle("Monospaced font", isOn: $menuBar.settings.appearance.monospaced)
                Picker("Weight", selection: $menuBar.settings.appearance.weight) {
                    ForEach(TrayFontWeight.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                adjustment("Size", value: $menuBar.settings.appearance.fontSize, range: 9...18, step: 0.5, display: String(format: "%.1f pt", menuBar.settings.appearance.fontSize))
                adjustment("Character width", value: $menuBar.settings.appearance.characterWidth, range: 50...150, step: 1, display: String(format: "%.0f%%", menuBar.settings.appearance.characterWidth))
                adjustment("Character spacing", value: $menuBar.settings.appearance.characterSpacing, range: -1...3, step: 0.1, display: String(format: "%+.1f pt", menuBar.settings.appearance.characterSpacing))
            }
            card("Format") {
                Stepper("Processor label gap: \(menuBar.settings.appearance.processorLabelSpacing) \(menuBar.settings.appearance.processorLabelSpacing == 1 ? "space" : "spaces")", value: $menuBar.settings.appearance.processorLabelSpacing, in: 0...3)
                Stepper("Label/value gap: \(menuBar.settings.appearance.valueSpacing) \(menuBar.settings.appearance.valueSpacing == 1 ? "space" : "spaces")", value: $menuBar.settings.appearance.valueSpacing, in: 0...3)
                Stepper("Between readings: \(menuBar.settings.appearance.groupSpacing) \(menuBar.settings.appearance.groupSpacing == 1 ? "space" : "spaces")", value: $menuBar.settings.appearance.groupSpacing, in: 0...4)
                Picker("Separator", selection: $menuBar.settings.separator) {
                    ForEach(StatSeparator.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Temperature", selection: $menuBar.settings.appearance.temperatureUnit) {
                    ForEach(TrayTemperatureUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Full processor labels (CPU / GPU)", isOn: $menuBar.settings.appearance.fullProcessorLabels)
                Toggle("Label RAM, power and battery", isOn: $menuBar.settings.appearance.systemLabels)
                Toggle("Battery symbols", isOn: $menuBar.settings.appearance.batterySymbols)
                    .disabled(menuBar.settings.appearance.monospaced)
            }
            HStack {
                Button("Reset appearance") { menuBar.settings.appearance = TrayAppearance() }
                Spacer()
                Text("System font is the default.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var generalPage: some View {
        VStack(spacing: 12) {
            card("Refresh interval") {
                RefreshIntervalPicker(selection: $monitor.intervalMs).frame(width: 280)
                Text("1 second is recommended.").font(.caption).foregroundStyle(.secondary)
            }
            card("Startup") {
                Toggle("Launch at login", isOn: loginBinding)
                if let error = launchError { Text(error).font(.caption).foregroundStyle(.red) }
            }
            card("Monitoring") {
                HStack {
                    Circle().fill(monitor.macmonRunning ? Color.mint : .red).frame(width: 8, height: 8)
                    Text(monitor.macmonRunning ? "macmon is running" : "macmon is offline")
                }
                if let error = monitor.macmonError { Text(error).font(.caption).foregroundStyle(.secondary) }
                Link("macmon on GitHub", destination: URL(string: "https://github.com/vladkens/macmon")!)
            }
        }
    }

    private var cardsPage: some View {
        VStack(spacing: 12) {
            card("All cards") {
                Picker("Style", selection: Binding(get: { menuBar.cardCharts.defaultStyle }, set: { menuBar.cardCharts.applyToAll($0) })) {
                    chartOptions
                }
                Text("Choosing a style here applies it to every card. You can customize individual cards below.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    ForEach(CardChartStyle.allCases.filter { $0 != .none }) { style in
                        VStack(spacing: 4) {
                            CardChart(style: style, history: [0.2, 0.3, 0.15, 0.5, 0.4, 0.7, 0.55], progress: 0.55, tint: .mint)
                                .frame(height: 24)
                            Text(style.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.top, 4)
            }
            card("CPU") {
                chartPicker("CPU usage", id: "cpu")
                ForEach(monitor.cpuTiers) { tier in
                    chartPicker(tier.displayName, id: "cpu-tier-\(tier.label)")
                }
                chartPicker("CPU temperature", id: "cpu-temp")
                chartPicker("CPU power", id: "cpu-power")
            }
            card("GPU & power") {
                chartPicker("GPU usage", id: "gpu")
                chartPicker("GPU temperature", id: "gpu-temp")
                chartPicker("GPU power", id: "gpu-power")
                chartPicker("Neural Engine power", id: "ane-power")
                chartPicker("System power", id: "system-power")
            }
            card("Memory & system") {
                chartPicker("RAM", id: "ram")
                chartPicker("Swap", id: "swap")
                chartPicker("Network download", id: "network")
                chartPicker("Battery", id: "battery")
                chartPicker("Disk free", id: "disk")
            }
            Text("Line and area graphs show recent history. Bars show the current level: usage, memory and battery as percentages, and disk as free capacity. Temperature uses 0–100 °C. Power scales are CPU 30 W, GPU 20 W, ANE 8 W and system 65 W. Network uses an adaptive scale.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Reset card styles") { menuBar.cardCharts = CardChartSettings() }
        }
    }

    private var chartOptions: some View {
        ForEach(CardChartStyle.allCases) { style in Text(style.title).tag(style) }
    }

    private func chartPicker(_ title: String, id: String) -> some View {
        Picker(title, selection: Binding(get: { menuBar.cardCharts.style(for: id) }, set: { menuBar.cardCharts.setStyle($0, for: id) })) {
            chartOptions
        }.accessibilityLabel("\(title) chart style")
    }

    private var previewLabel: String {
        (livePreview ? menuBar.currentReadings : MenuBarReadings.preview).label(settings: menuBar.settings)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Menu bar preview").font(.headline)
                Spacer()
                Picker("Preview data", selection: $livePreview) {
                    Text("Example").tag(false)
                    Text("Live").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 140)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                MenuBarPreviewLabel(text: previewLabel, appearance: menuBar.settings.appearance)
                    .frame(width: menuBar.settings.appearance.fixedWidthEnabled ? menuBar.settings.appearance.normalized.fixedWidth : MenuBarTypography.text(previewLabel, appearance: menuBar.settings.appearance).size().width + 8, height: 30)
            }.frame(height: 32)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func processorRow(_ name: String, usage: Binding<Bool>, temperature: Binding<Bool>) -> some View {
        HStack {
            Text(name).fontWeight(.medium).frame(width: 50, alignment: .leading)
            Toggle("Usage", isOn: usage).accessibilityLabel("\(name) usage")
            Toggle("Temperature", isOn: temperature).accessibilityLabel("\(name) temperature")
        }
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 125, alignment: .leading)
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
            Text(display).monospacedDigit().frame(width: 58, alignment: .trailing)
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { enabled in
            do {
                if enabled { try LoginItemManager.enable() }
                else { try LoginItemManager.disable() }
                launchAtLogin = enabled
                launchError = nil
            } catch { launchError = error.localizedDescription }
        })
    }
}
