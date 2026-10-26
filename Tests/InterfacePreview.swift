import AppKit
import SwiftUI

// Separate QA executable. Never included in the shipping application.
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var monitor: SystemMonitor?
    func applicationWillTerminate(_ notification: Notification) { monitor?.shutdown() }
}

@main
enum InterfacePreview {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let delegate = PreviewDelegate()
        NSApp.delegate = delegate
        let menu = NSMenu()
        let item = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit UI Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        let defaults = UserDefaults(suiteName: "sysdash.interface-preview")!
        defaults.set(1000, forKey: "sysdash.intervalMs")
        let monitor = SystemMonitor(macmonPath: Bundle.main.path(forResource: "fixture-helper", ofType: nil), defaults: defaults)
        delegate.monitor = monitor
        let manager = MenuBarManager()
        manager.setup(monitor: monitor)
        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(monitor: monitor, menuBar: manager)))
        window.title = "SYNTHETIC CPU TEST — SysDash 1.2"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 570))
        window.minSize = NSSize(width: 700, height: 520)
        manager.mainWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        withExtendedLifetime((delegate, manager, window)) { NSApp.run() }
    }
}
