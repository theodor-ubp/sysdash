import AppKit
import SwiftUI

@main
@MainActor
enum InterfaceSmokeTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func pickers(in view: NSView) -> [IntervalPickerContainer] {
        (view as? IntervalPickerContainer).map { [$0] } ?? view.subviews.flatMap { pickers(in: $0) }
    }

    static func settle(_ window: NSWindow) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let suite = "sysdash.interface.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = SystemMonitor(macmonPath: "/nonexistent/sysdash-test-helper", defaults: defaults)
        monitor.shutdown()
        let menuBar = MenuBarManager()
        let controller = NSHostingController(rootView: ContentView(monitor: monitor, menuBar: menuBar))
        let window = NSWindow(contentViewController: controller)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]

        var updates = 0
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            for size in [NSSize(width: 700, height: 488), NSSize(width: 820, height: 570), NSSize(width: 1200, height: 800)] {
                window.setContentSize(size)
                settle(window)
                guard let host = window.contentView, let picker = pickers(in: host).first else {
                    fatalError("Dashboard picker is missing")
                }
                let originalFrame = picker.convert(picker.bounds, to: host)
                check(abs(originalFrame.width - 170) < 0.5, "Dashboard picker width must be 170 points")
                let labelWidth = ("Refresh" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
                print("Picker frame \(originalFrame), label width \(labelWidth), host bounds \(host.bounds)")
                fflush(stdout)
                check(originalFrame.minX >= 16 + labelWidth + 5.5, "Picker overlaps the Refresh label")
                for i in 0..<30 {
                    var sample = original
                    sample["cpu_active_ratio"] = Double(i % 10) / 10
                    sample["gpu_active_ratio"] = Double((i + 3) % 10) / 10
                    sample["temp"] = ["cpu_temp_avg": i % 3 == 0 ? NSNull() : NSNumber(value: 40 + i), "gpu_temp_avg": NSNumber(value: 45 + i)]
                    let data = try JSONSerialization.data(withJSONObject: sample)
                    monitor.macmon = i % 7 == 0 ? nil : try decoder.decode(MacmonOutput.self, from: data)
                    monitor.macmonRunning = monitor.macmon != nil
                    monitor.cpuHistory = (0..<60).map { Double(($0 + i) % 10) / 10 }
                    monitor.networkDownBps = Double(i) * 1_048_576
                    monitor.hasBattery = i % 2 == 0
                    monitor.intervalMs = RefreshIntervalPicker.intervals[i % 4]
                    settle(window)
                    let frame = picker.convert(picker.bounds, to: host)
                    check(abs(frame.width - originalFrame.width) < 0.5, "Picker width changed during metric updates")
                    check(abs(frame.minX - originalFrame.minX) < 0.5, "Picker moved during metric updates")
                    check(abs(picker.control.frame.width - frame.width) < 0.5, "Native picker escaped its container")
                    for segment in 0..<4 {
                        check(abs(picker.control.width(forSegment: segment) - 42.5) < 0.5, "Segment width changed")
                    }
                    check(picker.control.selectedSegment == i % 4, "Picker selection did not follow the model")
                    updates += 1
                }
            }
        }
        print("PASS: dashboard picker stayed fixed through \(updates) updates, all selections, 3 window sizes, light/dark appearances and offline transitions")

        var selected = 1000
        let coordinator = RefreshIntervalPicker.Coordinator(selection: Binding(get: { selected }, set: { selected = $0 }))
        let standalone = IntervalPickerContainer(frame: NSRect(x: 0, y: 0, width: 170, height: 24))
        for width in [170.0, 292.0] {
            standalone.setFrameSize(NSSize(width: width, height: 20))
            standalone.layoutSubtreeIfNeeded()
            for index in 0..<4 {
                standalone.control.selectedSegment = index
                coordinator.selectionChanged(standalone.control)
                standalone.layoutSubtreeIfNeeded()
                check(selected == RefreshIntervalPicker.intervals[index], "Control action selected the wrong interval")
                check(abs(standalone.control.frame.width - width) < 0.5, "Settings picker escaped its container")
                for segment in 0..<4 {
                    check(abs(standalone.control.width(forSegment: segment) - width / 4) < 0.5, "Settings segment widths differ")
                }
            }
        }
        print("PASS: native refresh control actions map all four intervals correctly")

        let settings = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(menuBar: menuBar, monitor: monitor)))
        settings.setContentSize(NSSize(width: 368, height: 548))
        settle(settings)
        check(settings.contentView != nil, "Settings view did not lay out")
        let info = NSWindow(contentViewController: NSHostingController(rootView: InfoWindowView(monitor: monitor)))
        info.setContentSize(NSSize(width: 380, height: 260))
        settle(info)
        monitor.macmon = try decoder.decode(MacmonOutput.self, from: JSONSerialization.data(withJSONObject: original))
        settle(info)
        check(monitor.socInfo == monitor.macmon?.soc, "Hardware metadata did not arrive")
        monitor.macmon = nil
        settle(info)
        check(monitor.socInfo != nil, "Hardware metadata disappeared during an offline transition")
        print("PASS: Settings and Hardware Info lay out; Hardware Info observes arriving metrics")
    }
}
