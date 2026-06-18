import AppKit
import SwiftUI

// MARK: - Standalone onboarding window

final class OnboardingWindowHelper: NSObject {
    static let shared = OnboardingWindowHelper()
    private var window: NSWindow?

    func show(monitor: SystemMonitor, onComplete: @escaping () -> Void) {
        guard window == nil else { return }

        let root = OnboardingHostView(monitor: monitor) { [weak self] in
            self?.window?.close()
            self?.window = nil
            onComplete()
        }

        let vc = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: vc)
        win.styleMask  = [.titled, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.title = ""
        win.isMovableByWindowBackground = true
        win.isRestorable = false
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        window = win
    }
}

// MARK: - Host view (bridges Binding → closure)

private struct OnboardingHostView: View {
    let monitor: SystemMonitor
    let onComplete: () -> Void

    @State private var isPresented = true

    var body: some View {
        OnboardingView(monitor: monitor, isPresented: $isPresented)
            .onChange(of: isPresented) { stillShowing in
                if !stillShowing { onComplete() }
            }
    }
}
