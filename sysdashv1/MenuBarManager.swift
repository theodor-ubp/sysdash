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
    var separator    = StatSeparator.hyphen

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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
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

    func updateLabel() {
        guard let monitor else { return }
        var parts: [String] = []

        if let m = monitor.macmon {
            if settings.showCPU     { parts.append(String(format: "CPU %.0f%%",   m.cpuPct)) }
            if settings.showGPU     { parts.append(String(format: "GPU %.0f%%",   m.gpuPct)) }
            if settings.showCPUTemp { parts.append(String(format: "%.0f°",        m.temp.cpuTempAvg)) }
            if settings.showGPUTemp { parts.append(String(format: "G%.0f°",       m.temp.gpuTempAvg)) }
            if settings.showRAM     { parts.append(String(format: "%.1fGB",       m.ramUsedGB)) }
            if settings.showPower   { parts.append(String(format: "%.0fW",        m.sysPower)) }
        }
        if settings.showBattery {
            let icon = monitor.isCharging ? "⚡" : (monitor.isOnBattery ? "🔋" : "")
            parts.append(String(format: "%@%.0f%%", icon, monitor.batteryLevel))
        }
        if settings.showNetDown { parts.append(formatNetShort(monitor.networkDownBps, prefix: "↓")) }
        if settings.showNetUp   { parts.append(formatNetShort(monitor.networkUpBps,   prefix: "↑")) }

        let label = parts.isEmpty ? "UP Sysdash" : parts.joined(separator: settings.separator.rawValue)
        statusItem?.button?.title = label
        statusItem?.button?.toolTip = "UP Sysdash - right-click for stats"
    }

    private func formatNetShort(_ bps: Double, prefix: String) -> String {
        if bps >= 1_048_576 { return String(format: "%@%.1fM", prefix, bps / 1_048_576) }
        if bps >= 1_024     { return String(format: "%@%.0fK", prefix, bps / 1_024) }
        return String(format: "%@%.0fB", prefix, bps)
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
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
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
            settingsDelegate.manager = self
            win.delegate = settingsDelegate
            settingsWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showContextMenu() {
        let menu = NSMenu()

        if let m = monitor?.macmon {
            let cpu = NSMenuItem(title: String(format: "CPU  %.1f%%", m.cpuPct), action: nil, keyEquivalent: "")
            cpu.isEnabled = false
            menu.addItem(cpu)

            let gpu = NSMenuItem(title: String(format: "GPU  %.1f%%", m.gpuPct), action: nil, keyEquivalent: "")
            gpu.isEnabled = false
            menu.addItem(gpu)

            let temps = NSMenuItem(title: String(format: "CPU %.0f°  GPU %.0f°",
                                                 m.temp.cpuTempAvg, m.temp.gpuTempAvg),
                                   action: nil, keyEquivalent: "")
            temps.isEnabled = false
            menu.addItem(temps)

            let ram = NSMenuItem(title: String(format: "RAM  %.1f / %.0f GB",
                                               m.ramUsedGB, m.ramTotalGB),
                                 action: nil, keyEquivalent: "")
            ram.isEnabled = false
            menu.addItem(ram)

            let pwr = NSMenuItem(title: String(format: "Power  %.0f W", m.sysPower), action: nil, keyEquivalent: "")
            pwr.isEnabled = false
            menu.addItem(pwr)
        }

        if let mon = monitor {
            let upBps   = mon.networkUpBps
            let downBps = mon.networkDownBps
            if upBps > 0 || downBps > 0 {
                let net = NSMenuItem(title: "Net  ↓ \(formatNet(downBps))  ↑ \(formatNet(upBps))",
                                     action: nil, keyEquivalent: "")
                net.isEnabled = false
                menu.addItem(net)
            }

            if mon.batteryLevel > 0 {
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

    static func install() throws {
        guard let appPath = Bundle.main.bundlePath as String? else { return }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sysdash.app"
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>\(bundleID)</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>\(appPath)</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
"""
        let dir = "\(NSHomeDirectory())/Library/LaunchAgents"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"),
                             arguments: ["load", plistPath])
    }

    static func uninstall() throws {
        _ = try? Process.run(URL(fileURLWithPath: "/bin/launchctl"),
                             arguments: ["unload", plistPath])
        try FileManager.default.removeItem(atPath: plistPath)
    }
}
