import SwiftUI
import AppKit

final class AppCore {
    let monitor = SystemMonitor()
    let menuBar  = MenuBarManager()

    init() {
        menuBar.setup(monitor: monitor)
    }
}

@main
struct sysdashv1App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About UP Sysdash") {
                    AboutWindowHelper.open()
                }
                Button("Check for Updates…") {
                    UpdateChecker.shared.checkForUpdates(showIfUpToDate: true)
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let core = AppCore()
    private var launchCompleted = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenApplication),
            forEventClass: 0x61657674,
            andEventID:   0x6F617070
        )
        NSApp.setActivationPolicy(.prohibited)
    }

    @objc private func handleOpenApplication(_ event: NSAppleEventDescriptor,
                                             withReplyEvent: NSAppleEventDescriptor) {
        let isLoginItemStart = ProcessInfo.processInfo.systemUptime < 25
        if !isLoginItemStart {
            core.menuBar.openMainWindow()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            UpdateChecker.shared.checkForUpdates(showIfUpToDate: false)
        }
        launchCompleted = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        guard launchCompleted else { return false }
        if !hasVisibleWindows {
            core.menuBar.openMainWindow()
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
