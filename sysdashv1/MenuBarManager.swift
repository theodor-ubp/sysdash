import AppKit
import Combine
import SwiftUI
import ServiceManagement

// MARK: - Persisted menu bar preferences

enum StatSeparator: String, Codable, CaseIterable {
    case none   = " "
    case hyphen = " - "
    case pipe   = " | "
    case slash  = " / "

    func text(spacing: Int) -> String {
        let spaces = String(repeating: " ", count: min(max(spacing, 0), 4))
        return self == .none ? spaces : spaces + rawValue.trimmingCharacters(in: .whitespaces) + spaces
    }

    var label: String {
        switch self {
        case .none:   return "None"
        case .hyphen: return "Hyphen  ( - )"
        case .pipe:   return "Pipe  ( | )"
        case .slash:  return "Slash  ( / )"
        }
    }
}

struct MenuBarSettings: Codable, Equatable {
    var showCPU      = true
    var showGPU      = false
    var showCPUTemp  = false
    var showGPUTemp  = false
    var showRAM      = false
    var showPower    = false
    var showBattery  = false
    var showNetDown  = false
    var showNetUp    = false
    var separator    = StatSeparator.none
    var appearance   = TrayAppearance()

    private enum CodingKeys: String, CodingKey {
        case showCPU, showGPU, showCPUTemp, showGPUTemp, showRAM, showPower, showBattery, showNetDown, showNetUp, separator, appearance
    }

    static func load() -> MenuBarSettings {
        guard let data = UserDefaults.standard.data(forKey: "sysdash.menuBarSettings"),
              let s = try? JSONDecoder().decode(MenuBarSettings.self, from: data)
        else { return MenuBarSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "sysdash.menuBarSettings")
        }
    }
}

extension MenuBarSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showCPU = try c.decodeIfPresent(Bool.self, forKey: .showCPU) ?? showCPU
        showGPU = try c.decodeIfPresent(Bool.self, forKey: .showGPU) ?? showGPU
        showCPUTemp = try c.decodeIfPresent(Bool.self, forKey: .showCPUTemp) ?? showCPUTemp
        showGPUTemp = try c.decodeIfPresent(Bool.self, forKey: .showGPUTemp) ?? showGPUTemp
        showRAM = try c.decodeIfPresent(Bool.self, forKey: .showRAM) ?? showRAM
        showPower = try c.decodeIfPresent(Bool.self, forKey: .showPower) ?? showPower
        showBattery = try c.decodeIfPresent(Bool.self, forKey: .showBattery) ?? showBattery
        showNetDown = try c.decodeIfPresent(Bool.self, forKey: .showNetDown) ?? showNetDown
        showNetUp = try c.decodeIfPresent(Bool.self, forKey: .showNetUp) ?? showNetUp
        separator = try c.decodeIfPresent(StatSeparator.self, forKey: .separator) ?? separator
        appearance = (try? c.decode(TrayAppearance.self, forKey: .appearance)) ?? TrayAppearance()
    }
}

// MARK: - MenuBarManager

// Clears statusItem.menu after the context menu closes so left-click still works
private final class MenuContextDelegate: NSObject, NSMenuDelegate {
    weak var statusItem: NSStatusItem?
    func menuDidClose(_ menu: NSMenu) { statusItem?.menu = nil }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    weak var manager: MenuBarManager?
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        manager?.settingsWindow = nil
        DispatchQueue.main.async {
            let anyOtherVisible = NSApp.windows.contains {
                $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
            }
            if !anyOtherVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

final class MenuBarManager: ObservableObject {
    @Published var settings = MenuBarSettings.load()
    @Published var cardCharts = CardChartSettings.load()

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private weak var monitor: SystemMonitor?
    private let menuDelegate = MenuContextDelegate()

    var mainWindow: NSWindow?
    private var mainWinDelegate: MinSizeWindowDelegate?

    var settingsWindow: NSWindow?
    private let settingsDelegate = SettingsWindowDelegate()

    func setup(monitor: SystemMonitor) {
        self.monitor = monitor

        let appearance = settings.appearance.normalized
        statusItem = NSStatusBar.system.statusItem(withLength: appearance.fixedWidthEnabled ? appearance.fixedWidth : NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.font = MenuBarTypography.font(appearance: settings.appearance)
            btn.action = #selector(statusItemClicked)
            btn.target  = self
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        monitor.$macmon
            .combineLatest(monitor.$batteryLevel, monitor.$isOnBattery, monitor.$isCharging)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        monitor.$networkDownBps
            .combineLatest(monitor.$networkUpBps)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        $settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLabel() }
            .store(in: &cancellables)

        updateLabel()
    }

    func saveSettings() { settings.save() }

    // MARK: - Label

    var currentReadings: MenuBarReadings {
        guard let monitor else { return MenuBarReadings() }
        let m = monitor.macmon
        return MenuBarReadings(cpuPercent: m?.cpuPct,
            gpuPercent: monitor.gpuAvailable ? m?.gpuPct : nil,
            cpuTemperature: m?.temp.cpuTempAvg, gpuTemperature: m?.temp.gpuTempAvg,
            ramGB: m?.ramUsedGB, systemWatts: monitor.powerAvailable ? m?.sysPower : nil,
            batteryPercent: monitor.hasBattery ? monitor.batteryLevel : nil,
            isCharging: monitor.isCharging, isOnBattery: monitor.isOnBattery,
            downloadBps: m == nil ? nil : monitor.networkDownBps, uploadBps: m == nil ? nil : monitor.networkUpBps)
    }

    func updateLabel() {
        let readings = currentReadings
        let label = readings.label(settings: settings)
        let appearance = settings.appearance.normalized
        guard let item = statusItem, let button = item.button else { return }
        if appearance.fixedWidthEnabled {
            if item.length != appearance.fixedWidth { item.length = appearance.fixedWidth }
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.image = MenuBarTypography.fixedWidthImage(label, appearance: appearance)
        } else {
            if item.length != NSStatusItem.variableLength { item.length = NSStatusItem.variableLength }
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = MenuBarTypography.text(label, appearance: appearance)
        }
        button.setAccessibilityLabel(label)
        button.toolTip = "\(label)\nUP Sysdash - right-click for stats"
    }

    // MARK: - Click

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            openMainWindow()
        }
    }

    @objc func openMainWindow() {
        if let win = mainWindow, win.isVisible {
            win.orderOut(nil)
            DispatchQueue.main.async {
                let anyVisible = NSApp.windows.contains {
                    $0.isVisible && $0.styleMask.contains(.titled)
                }
                if !anyVisible { NSApp.setActivationPolicy(.accessory) }
            }
            return
        }
        showMainWindow()
        if !UserDefaults.standard.bool(forKey: "sysdash.onboardingDone") {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            guard let self, let monitor = self.monitor else { return }
            OnboardingWindowHelper.shared.show(monitor: monitor) { [weak self] in
                UserDefaults.standard.set(true, forKey: "sysdash.onboardingDone")
                self?.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showMainWindow() {
        if mainWindow == nil {
            guard let monitor = monitor else { return }
            let vc = NSHostingController(
                rootView: ContentView(monitor: monitor, menuBar: self)
            )
            let win = NSWindow(contentViewController: vc)
            win.title = "UP Sysdash"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setFrameAutosaveName("SysDashMain")
            win.isRestorable = false
            if UserDefaults.standard.string(forKey: "NSWindow Frame SysDashMain") == nil {
                let sz = NSSize(width: 820, height: 570)
                win.setContentSize(sz)
                if let scr = NSScreen.main {
                    let f = scr.visibleFrame
                    win.setFrameOrigin(
                        NSPoint(x: f.maxX - sz.width - 10, y: f.maxY - sz.height - 10)
                    )
                }
            }
            let del = MinSizeWindowDelegate(minSize: NSSize(width: 700, height: 520))
            win.delegate = del
            mainWinDelegate = del
            mainWindow = win
        }

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.mainWindow?.makeKeyAndOrderFront(nil)
            self?.mainWindow?.orderFrontRegardless()
        }
    }

    func setWindowLevel(floating: Bool) {
        mainWindow?.level = floating ? .floating : .normal
        settingsWindow?.level = floating ? .floating : .normal
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func checkForUpdatesFromMenu() {
        UpdateChecker.shared.checkForUpdates(showIfUpToDate: true)
    }

    func openSettings() {
        if settingsWindow == nil {
            guard let monitor = monitor else { return }
            let vc = NSHostingController(rootView: SettingsView(menuBar: self, monitor: monitor))
            let win = NSWindow(contentViewController: vc)
            win.title = "SysDash Settings"
            win.styleMask = [.titled, .closable]
            win.isRestorable = false
            win.setFrameAutosaveName("SysDashSettings")
            win.setContentSize(NSSize(width: 720, height: 600))
            settingsDelegate.manager = self
            win.delegate = settingsDelegate
            settingsWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.level = mainWindow?.level ?? .normal
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if let m = monitor?.macmon {
            let cpu = NSMenuItem(title: String(format: "CPU  %.1f%%", m.cpuPct), action: nil, keyEquivalent: "")
            cpu.isEnabled = false
            menu.addItem(cpu)

            let gpu = NSMenuItem(title: monitor?.gpuAvailable == true ? String(format: "GPU  %.1f%%", m.gpuPct) : "GPU  —", action: nil, keyEquivalent: "")
            gpu.isEnabled = false
            menu.addItem(gpu)

            let temps = NSMenuItem(title: "CPU \(formatTemperature(m.temp.cpuTempAvg))  GPU \(formatTemperature(m.temp.gpuTempAvg))",
                                   action: nil, keyEquivalent: "")
            temps.isEnabled = false
            menu.addItem(temps)

            let ram = NSMenuItem(title: String(format: "RAM  %.1f / %.0f GB",
                                               m.ramUsedGB, m.ramTotalGB),
                                 action: nil, keyEquivalent: "")
            ram.isEnabled = false
            menu.addItem(ram)

            let pwr = NSMenuItem(title: monitor?.powerAvailable == true ? String(format: "Power  %.0f W", m.sysPower) : "Power  —", action: nil, keyEquivalent: "")
            pwr.isEnabled = false
            menu.addItem(pwr)
        }

        if let mon = monitor {
            let upBps   = mon.networkUpBps
            let downBps = mon.networkDownBps
            if mon.macmon != nil, upBps > 0 || downBps > 0 {
                let net = NSMenuItem(title: "Net  ↓ \(formatNet(downBps))  ↑ \(formatNet(upBps))",
                                     action: nil, keyEquivalent: "")
                net.isEnabled = false
                menu.addItem(net)
            }

            if mon.hasBattery {
                let icon = mon.isCharging ? "⚡" : (mon.isOnBattery ? "🔋" : "🔌")
                let bat = NSMenuItem(title: String(format: "Battery  %@%.0f%%", icon, mon.batteryLevel),
                                     action: nil, keyEquivalent: "")
                bat.isEnabled = false
                menu.addItem(bat)
            }
        }

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open UP Sysdash", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit UP Sysdash", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        menuDelegate.statusItem = statusItem
        menu.delegate = menuDelegate
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
    }

    // MARK: - Network formatting

    private func formatNet(_ bps: Double) -> String {
        if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
        if bps >= 1_024     { return String(format: "%.0f KB/s", bps / 1_024) }
        return String(format: "%.0f B/s", bps)
    }
}

// MARK: - Login item manager (unified macOS 12/13+ abstraction)

enum LoginItemManager {

    static var isEnabled: Bool {
        if #available(macOS 13, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return LaunchAgentHelper.isInstalled
    }

    static func enable() throws {
        if #available(macOS 13, *) {
            try SMAppService.mainApp.register()
        } else {
            try LaunchAgentHelper.install()
        }
    }

    static func disable() throws {
        if #available(macOS 13, *) {
            try SMAppService.mainApp.unregister()
        } else {
            try LaunchAgentHelper.uninstall()
        }
    }
}

// MARK: - LaunchAgent helper (macOS 12 fallback)

enum LaunchAgentHelper {
    static var plistPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/com.sysdash.app.plist"
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    static func plistData(appPath: String, bundleID: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "Label": bundleID,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true
        ], format: .xml, options: 0)
    }

    static func install() throws {
        guard let appPath = Bundle.main.bundlePath as String? else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sysdash.app"
        let plist = try plistData(appPath: appPath, bundleID: bundleID)
        let dir = "\(NSHomeDirectory())/Library/LaunchAgents"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try plist.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"),
                             arguments: ["load", plistPath])
    }

    static func uninstall() throws {
        _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"),
                             arguments: ["unload", plistPath])
        try FileManager.default.removeItem(atPath: plistPath)
    }
}
