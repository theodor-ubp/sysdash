import AppKit
import SwiftUI

// Keep AppKit's segmented control inside a constrained container. SwiftUI's
// segmented Picker can change its intrinsic width during macOS 27 updates.
struct RefreshIntervalPicker: NSViewRepresentable {
    @Binding var selection: Int
    static let intervals = [500, 1000, 2000, 5000]

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> IntervalPickerContainer {
        let view = IntervalPickerContainer()
        view.control.target = context.coordinator
        view.control.action = #selector(Coordinator.selectionChanged(_:))
        return view
    }

    func updateNSView(_ view: IntervalPickerContainer, context: Context) {
        context.coordinator.selection = $selection
        let index = Self.intervals.firstIndex(of: selection) ?? 1
        if view.control.selectedSegment != index { view.control.selectedSegment = index }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard RefreshIntervalPicker.intervals.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = RefreshIntervalPicker.intervals[sender.selectedSegment]
        }
    }
}

final class IntervalPickerContainer: NSView {
    let control = NSSegmentedControl(labels: ["0.5s", "1s", "2s", "5s"],
                                    trackingMode: .selectOne, target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        control.segmentStyle = .rounded
        control.controlSize = .small
        control.font = .systemFont(ofSize: 11)
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel("Refresh interval")
        control.setAccessibilityIdentifier("refreshIntervalPicker")
        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.topAnchor.constraint(equalTo: topAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 170, height: control.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width / CGFloat(control.segmentCount))
        for segment in 0..<control.segmentCount where control.width(forSegment: segment) != width {
            control.setWidth(width, forSegment: segment)
        }
    }
}
