import SwiftUI
import AppKit

// MARK: - About window opener

enum AboutWindowHelper {
    private static var window: NSWindow?

    static func open() {
        if window == nil {
            let vc = NSHostingController(rootView: AboutView())
            let win = NSWindow(contentViewController: vc)
            win.title = "About UP Sysdash"
            win.styleMask = [.titled, .closable]
            win.isRestorable = false
            win.setFrameAutosaveName("")
            win.setContentSize(NSSize(width: 500, height: 370))
            win.center()
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - About view

struct AboutView: View {

    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }()

    var body: some View {
        ZStack {
            Color(red: 0.059, green: 0.059, blue: 0.059)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                logoSection
                    .padding(.top, 32)

                HStack(spacing: 6) {
                    Text("UP Sysdash \(appVersion)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("-")
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                        .font(.system(size: 13))
                    linkButton("GitHub", url: "https://github.com/theodor-ubp/sysdash")
                    linkButton("Ko-fi", url: "https://ko-fi.com/tehodor9449790")
                }
                .padding(.top, 18)

                Text("UP Sysdash is a native macOS system monitor for Apple Silicon. CPU, GPU, memory, power, temps, network, battery - live in your menu bar.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.78, green: 0.78, blue: 0.78))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .frame(width: 420, alignment: .leading)
                    .padding(.top, 16)

                linkButton("unboundplanet.com", url: "https://unboundplanet.com/")
                    .font(.system(size: 12))
                    .padding(.top, 12)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 40)
                    .padding(.top, 20)

                HStack(spacing: 4) {
                    Text("Uses")
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    linkButton("macmon", url: "https://github.com/vladkens/macmon")
                    Text("by vladkens, MIT licensed.")
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                }
                .font(.system(size: 11))
                .padding(.top, 14)

                Spacer()
            }
            .frame(width: 500)
        }
        .frame(width: 500, height: 370)
    }

    // MARK: - Logo section

    private var logoSection: some View {
        Button {
            if let url = URL(string: "https://unboundplanet.com/") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Group {
                if let img = NSImage(named: "unbound") {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 110)
                } else {
                    Text("UNBOUND")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                        .frame(width: 240, height: 110)
                }
            }
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    // MARK: - Link button

    private func linkButton(_ title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            Text(title)
                .underline()
                .foregroundColor(Color(red: 0.302, green: 0.651, blue: 1.0))
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}

// MARK: - Pointing hand cursor modifier

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
