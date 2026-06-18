import SwiftUI

struct SettingsView: View {
    @ObservedObject var menuBar: MenuBarManager
    @ObservedObject var monitor: SystemMonitor

    @State private var launchAtLogin = LoginItemManager.isEnabled
    @State private var launchError: String?

    var body: some View {
        TabView {
            menuBarTab
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 360, height: 540)
        .padding(4)
    }

    // MARK: - Menu Bar tab

    private var menuBarTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsGroupHeader("Show in Menu Bar")
            settingsGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("CPU Usage",       isOn: $menuBar.settings.showCPU)
                    Toggle("GPU Usage",       isOn: $menuBar.settings.showGPU)
                    Toggle("CPU Temperature", isOn: $menuBar.settings.showCPUTemp)
                    Toggle("GPU Temperature", isOn: $menuBar.settings.showGPUTemp)
                    Toggle("RAM Used",        isOn: $menuBar.settings.showRAM)
                    Toggle("System Power",    isOn: $menuBar.settings.showPower)
                    Toggle("Battery",         isOn: $menuBar.settings.showBattery)
                    Toggle("Net Download",    isOn: $menuBar.settings.showNetDown)
                    Toggle("Net Upload",      isOn: $menuBar.settings.showNetUp)
                }
            }
            .onChange(of: menuBar.settings) { _ in menuBar.saveSettings() }

            settingsGroupHeader("Separator")
            settingsGroup {
                Picker("", selection: $menuBar.settings.separator) {
                    ForEach(StatSeparator.allCases, id: \.self) { sep in
                        Text(sep.label).tag(sep)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: menuBar.settings) { _ in menuBar.saveSettings() }

            settingsGroupHeader("Preview")
            settingsGroup {
                Text(previewLabel)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var previewLabel: String {
        var parts: [String] = []
        if menuBar.settings.showCPU     { parts.append("CPU 28%") }
        if menuBar.settings.showGPU     { parts.append("GPU 5%") }
        if menuBar.settings.showCPUTemp { parts.append("45°") }
        if menuBar.settings.showGPUTemp { parts.append("G38°") }
        if menuBar.settings.showRAM     { parts.append("7.4GB") }
        if menuBar.settings.showPower   { parts.append("6W") }
        if menuBar.settings.showBattery  { parts.append("⚡100%") }
        if menuBar.settings.showNetDown  { parts.append("↓1.2M") }
        if menuBar.settings.showNetUp    { parts.append("↑500K") }
        return parts.isEmpty ? "SysDash" : parts.joined(separator: menuBar.settings.separator.rawValue)
    }

    // MARK: - General tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsGroupHeader("Refresh Interval")
            settingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $monitor.intervalMs) {
                        Text("0.5 s").tag(500)
                        Text("1 s").tag(1000)
                        Text("2 s").tag(2000)
                        Text("5 s").tag(5000)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Lower intervals use more CPU. 1 s recommended.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            settingsGroupHeader("Startup")
            settingsGroup {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled { try LoginItemManager.enable() }
                                else       { try LoginItemManager.disable() }
                                launchError = nil
                            } catch {
                                launchError = error.localizedDescription
                                launchAtLogin = !enabled
                            }
                        }
                    if let err = launchError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }

            settingsGroupHeader("macmon Status")
            settingsGroup {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitor.macmonRunning ? Color.mint : Color.red)
                            .frame(width: 8, height: 8)
                        Text(monitor.macmonRunning ? "Running" : "Not running")
                    }
                    if let err = monitor.macmonError {
                        Text(err).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Link("macmon on GitHub",
                         destination: URL(string: "https://github.com/vladkens/macmon")!)
                        .font(.caption)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func settingsGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 4)
            .padding(.top, 10)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 2)
    }
}
