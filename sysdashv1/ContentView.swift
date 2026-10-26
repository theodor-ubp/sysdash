import SwiftUI
import AppKit
import Darwin  // sysctlbyname

// MARK: - Window accessor helper

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowFinderView { WindowFinderView(callback: callback) }
    func updateNSView(_ v: WindowFinderView, context: Context) {}
}

final class WindowFinderView: NSView {
    let callback: (NSWindow) -> Void
    private var fired = false
    init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !fired, let win = window else { return }
        fired = true
        callback(win)
    }
}

// MARK: - Min-size window delegate

class MinSizeWindowDelegate: NSObject, NSWindowDelegate {
    let minSize: NSSize
    init(minSize: NSSize) { self.minSize = minSize }

    func windowWillResize(_ sender: NSWindow, to s: NSSize) -> NSSize {
        NSSize(width: max(s.width, minSize.width), height: max(s.height, minSize.height))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        retractToAccessoryIfIdle()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let sender = notification.object as? NSWindow else { return }
        sender.deminiaturize(nil)
        sender.orderOut(nil)
        retractToAccessoryIfIdle()
    }

    private func retractToAccessoryIfIdle() {
        DispatchQueue.main.async {
            let anyVisible = NSApp.windows.contains {
                $0.isVisible && $0.styleMask.contains(.titled)
            }
            if !anyVisible { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let data: [Double]   // 0–1 normalised
    let tint: Color
    var area = false

    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            // Keep strokes and the 2.5-point endpoint inside the chart itself.
            let inset: CGFloat = 3
            let w = size.width - inset * 2
            let h = size.height - inset * 2
            guard w > 0, h > 0 else { return }
            let step = w / CGFloat(data.count - 1)

            func yPosition(_ value: Double) -> CGFloat {
                let normalised = value.isFinite ? min(max(value, 0), 1) : 0
                return inset + h - CGFloat(normalised) * h
            }

            var path = Path()
            for (i, v) in data.enumerated() {
                let x = inset + CGFloat(i) * step
                let y = yPosition(v)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else       { path.addLine(to: CGPoint(x: x, y: y)) }
            }

            var fill = path
            let lastX = inset + CGFloat(data.count - 1) * step
            fill.addLine(to: CGPoint(x: lastX, y: inset + h))
            fill.addLine(to: CGPoint(x: inset, y: inset + h))
            fill.closeSubpath()

            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [tint.opacity(area ? 0.6 : 0.22), tint.opacity(area ? 0.12 : 0.0)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint:   CGPoint(x: 0, y: h)
            ))

            ctx.stroke(path,
                       with: .color(tint.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            if !area, let last = data.last {
                let cx = lastX
                let cy = yPosition(last)
                var dot = Path()
                dot.addEllipse(in: CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5))
                ctx.fill(dot, with: .color(tint))
            }
        }
        .clipped()
    }
}

// MARK: - Network formatting

private func formatNet(_ bps: Double) -> String {
    if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
    if bps >= 1_024     { return String(format: "%.0f KB/s", bps / 1_024) }
    return String(format: "%.0f B/s", bps)
}

// MARK: - Metric card

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String?
    let progress: Double   // 0..1
    let tint: Color
    var history: [Double]? = nil   // optional sparkline data
    var chartStyle = CardChartStyle.line
    var chartAvailable = true

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 5)

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            if let d = detail {
                Text(d)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 3)
            }

            Spacer(minLength: 4)

            CardChart(style: chartStyle, history: history ?? [], progress: progress, tint: tint, available: chartAvailable)
                .frame(height: 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .brightness(hovered ? 0.05 : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(tint.opacity(hovered ? 0.45 : 0.22), lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { h in hovered = h }
    }
}

// MARK: - Section divider

struct SectionDivider: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
    }
}

// MARK: - Color helpers

private func tempColor(_ c: Double) -> Color {
    if c < 60 { return .mint }
    if c < 80 { return .yellow }
    return .red
}

private func batteryColor(_ pct: Double, onBattery: Bool) -> Color {
    if !onBattery { return .mint }
    if pct > 40 { return .mint }
    if pct > 20 { return .yellow }
    return .red
}

private func usageColor(_ pct: Double, normal: Color) -> Color {
    if pct < 70 { return normal }
    if pct < 90 { return .yellow }
    return .red
}

// MARK: - Notification names

extension Notification.Name {
    static let bringToFront = Notification.Name("sysdash.bringToFront")
}

// MARK: - Main ContentView

struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var menuBar: MenuBarManager

    @State private var alwaysOnTop = false
    @State private var infoWindow: NSWindow?
    @State private var infoWindowDelegate: MinSizeWindowDelegate?
    @State private var livePulse = false


    private var m: MacmonOutput? { monitor.macmon }
    private var soc: MacmonSocInfo? { monitor.socInfo }

    private func powerValue(_ value: Double?, precision: Int = 1) -> String {
        guard monitor.powerAvailable, let value else { return "—" }
        return String(format: "%.*f W", precision, value)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    SectionDivider(title: "CPU")
                    cpuRow

                    SectionDivider(title: "GPU  -  POWER")
                    gpuPowerRow

                    SectionDivider(title: "MEMORY  -  SYSTEM")
                    memorySystemRow

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            Divider()
            controlBar
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("UP Sysdash")
                    .font(.system(size: 17, weight: .bold))
                if let s = soc {
                    Text("\(s.chipName) - \(s.coreLabel) - \(s.memoryGb) GB")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(monitor.macmonRunning ? "Connecting…" : (monitor.macmonError != nil ? "macmon offline" : "Starting…"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Status dot — pulses when live
            HStack(spacing: 4) {
                Circle()
                    .fill(monitor.macmonRunning ? Color.mint : Color.red)
                    .frame(width: 7, height: 7)
                    .opacity(monitor.macmonRunning ? (livePulse ? 0.3 : 1.0) : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: livePulse)
                    .onAppear { livePulse = true }
                Text(monitor.macmonRunning ? "Live" : "Offline")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Activity Monitor shortcut
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().scaledToFit().frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }

            // Settings
            Button { menuBar.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - CPU row

    private var cpuRow: some View {
        HStack(spacing: 10) {
            // Combined CPU
            let cpuPct = m?.cpuPct ?? 0
            MetricCard(
                label: "CPU",
                value: m.map { String(format: "%.1f%%", $0.cpuPct) } ?? "—",
                detail: "Active, core-weighted",
                progress: cpuPct / 100,
                tint: usageColor(cpuPct, normal: .mint),
                history: monitor.cpuHistory,
                chartStyle: menuBar.cardCharts.style(for: "cpu"),
                chartAvailable: m != nil
            )

            ForEach(monitor.cpuTiers) { tier in
                cpuTierCard(tier)
            }

            // CPU temperature
            let cpuTemp = m?.temp.cpuTempAvg ?? 0
            MetricCard(
                label: "CPU TEMP",
                value: formatTemperature(m?.temp.cpuTempAvg, suffix: " °C"),
                detail: nil,
                progress: cpuTemp / 100,
                tint: tempColor(cpuTemp),
                history: monitor.cpuTempHistory,
                chartStyle: menuBar.cardCharts.style(for: "cpu-temp"),
                chartAvailable: m?.temp.cpuTempAvg != nil
            )

            // CPU power
            MetricCard(
                label: "CPU POWER",
                value: powerValue(m?.cpuPower),
                detail: nil,
                progress: m.map { $0.cpuPower / 30 } ?? 0,
                tint: .orange,
                history: monitor.cpuPowerHistory,
                chartStyle: menuBar.cardCharts.style(for: "cpu-power"),
                chartAvailable: monitor.powerAvailable && m != nil
            )
        }
    }

    private func cpuTierCard(_ tier: MacmonCPUTierInfo) -> some View {
        let metrics = m?.tiers.first { $0.label == tier.label }
        let percent = metrics?.percent ?? 0
        let tint: Color = tier.label == "E" ? .cyan : (tier.label == "S" ? .indigo : .blue)
        let frequency = soc?.vm == true ? nil : metrics?.freqMhz
        return MetricCard(
            label: tier.displayName,
            value: soc?.vm == true ? metrics.map { String(format: "%.1f%%", $0.percent) } ?? "—" : formatFrequency(frequency),
            detail: metrics.map { String(format: "%.1f%% - %d cores", $0.percent, tier.cores) },
            progress: percent / 100,
            tint: usageColor(percent, normal: tint),
            history: monitor.cpuTierHistory[tier.label],
            chartStyle: menuBar.cardCharts.style(for: "cpu-tier-\(tier.label)"),
            chartAvailable: metrics != nil
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cpu-tier-\(tier.label)")
    }

    // MARK: - GPU + Power row

    private var gpuPowerRow: some View {
        HStack(spacing: 10) {
            // GPU usage + freq
            let gpuPct = m?.gpuPct ?? 0
            MetricCard(
                label: "GPU",
                value: monitor.gpuAvailable ? m.map { String(format: "%.1f%%", $0.gpuPct) } ?? "—" : "—",
                detail: monitor.gpuAvailable ? m.map { "\(formatFrequency($0.gpuFreqMHz)) - \(soc?.gpuCores ?? 0) cores" } : "Unavailable",
                progress: monitor.gpuAvailable ? gpuPct / 100 : 0,
                tint: usageColor(gpuPct, normal: .purple),
                history: monitor.gpuHistory,
                chartStyle: menuBar.cardCharts.style(for: "gpu"),
                chartAvailable: monitor.gpuAvailable && m != nil
            )

            // GPU temperature
            let gpuTemp = m?.temp.gpuTempAvg ?? 0
            MetricCard(
                label: "GPU TEMP",
                value: formatTemperature(m?.temp.gpuTempAvg, suffix: " °C"),
                detail: nil,
                progress: gpuTemp / 100,
                tint: tempColor(gpuTemp),
                history: monitor.gpuTempHistory,
                chartStyle: menuBar.cardCharts.style(for: "gpu-temp"),
                chartAvailable: m?.temp.gpuTempAvg != nil
            )

            // GPU power
            MetricCard(
                label: "GPU POWER",
                value: powerValue(m?.gpuPower),
                detail: nil,
                progress: m.map { $0.gpuPower / 20 } ?? 0,
                tint: .orange,
                history: monitor.gpuPowerHistory,
                chartStyle: menuBar.cardCharts.style(for: "gpu-power"),
                chartAvailable: monitor.powerAvailable && m != nil
            )

            // ANE power
            MetricCard(
                label: "ANE POWER",
                value: powerValue(m?.anePower, precision: 2),
                detail: "Neural Engine",
                progress: m.map { $0.anePower / 8 } ?? 0,
                tint: .yellow,
                history: monitor.anePowerHistory,
                chartStyle: menuBar.cardCharts.style(for: "ane-power"),
                chartAvailable: monitor.powerAvailable && m != nil
            )

            // Total system power
            MetricCard(
                label: "SYS POWER",
                value: powerValue(m?.sysPower),
                detail: monitor.powerAvailable ? m.map { String(format: "chip %.1f W", $0.allPower) } : "Unavailable",
                progress: m.map { $0.sysPower / 65 } ?? 0,
                tint: .orange,
                history: monitor.sysPowerHistory,
                chartStyle: menuBar.cardCharts.style(for: "system-power"),
                chartAvailable: monitor.powerAvailable && m != nil
            )
        }
    }

    // MARK: - Memory + System row

    private var memorySystemRow: some View {
        HStack(spacing: 10) {
            // RAM
            let ramPct = m?.ramPct ?? 0
            MetricCard(
                label: "RAM",
                value: m.map { String(format: "%.1f GB", $0.ramUsedGB) } ?? "—",
                detail: m.map { String(format: "of %.0f GB  -  %.0f%%", $0.ramTotalGB, $0.ramPct) },
                progress: ramPct / 100,
                tint: usageColor(ramPct, normal: .green),
                history: monitor.ramHistory,
                chartStyle: menuBar.cardCharts.style(for: "ram"),
                chartAvailable: m != nil
            )

            // Swap
            let hasSwap = (m?.swapTotalGB ?? 0) > 0.01
            MetricCard(
                label: "SWAP",
                value: m.map { $0.swapTotalGB < 0.01 ? "None" : String(format: "%.1f GB", $0.swapUsedGB) } ?? "—",
                detail: hasSwap ? m.map { String(format: "of %.1f GB", $0.swapTotalGB) } : nil,
                progress: hasSwap ? m.map { $0.swapTotalGB > 0 ? $0.swapUsedGB / $0.swapTotalGB : 0 } ?? 0 : 0,
                tint: .teal,
                history: monitor.swapHistory,
                chartStyle: menuBar.cardCharts.style(for: "swap"),
                chartAvailable: m != nil
            )

            // Network I/O
            MetricCard(
                label: "NETWORK",
                value: m == nil ? "—" : "↓ \(formatNet(monitor.networkDownBps))",
                detail: m == nil ? "Unavailable" : "↑ \(formatNet(monitor.networkUpBps))",
                progress: monitor.netDownHistory.last ?? 0,
                tint: .indigo,
                history: monitor.netDownHistory,
                chartStyle: menuBar.cardCharts.style(for: "network"),
                chartAvailable: m != nil
            )

            // Battery
            let batColor = batteryColor(monitor.batteryLevel, onBattery: monitor.isOnBattery)
            MetricCard(
                label: "BATTERY",
                value: monitor.hasBattery ? String(format: "%.0f%%", monitor.batteryLevel) : "—",
                detail: monitor.hasBattery ? (monitor.isCharging ? "Charging ⚡" : (monitor.isOnBattery ? "On battery 🔋" : "Plugged in 🔌")) : "No battery",
                progress: monitor.batteryLevel / 100,
                tint: batColor,
                history: monitor.batteryHistory,
                chartStyle: menuBar.cardCharts.style(for: "battery"),
                chartAvailable: monitor.hasBattery
            )

            // Disk
            let diskPct = monitor.diskTotalGB > 0 ? (monitor.diskTotalGB - monitor.diskFreeGB) / monitor.diskTotalGB : 0
            MetricCard(
                label: "DISK FREE",
                value: String(format: "%.0f GB", monitor.diskFreeGB),
                detail: String(format: "of %.0f GB  -  %.0f%% used", monitor.diskTotalGB, diskPct * 100),
                progress: monitor.diskTotalGB > 0 ? monitor.diskFreeGB / monitor.diskTotalGB : 0,
                tint: usageColor(diskPct * 100, normal: .gray),
                history: monitor.diskFreeHistory,
                chartStyle: menuBar.cardCharts.style(for: "disk"),
                chartAvailable: monitor.diskTotalGB > 0
            )
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 16) {
            // Interval picker
            HStack(spacing: 6) {
                Text("Refresh")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                RefreshIntervalPicker(selection: $monitor.intervalMs)
                .frame(width: 170)
                .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize()

            Spacer()

            Button("Hardware Info") { openInfoWindow() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Button("About") { AboutWindowHelper.open() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Toggle("Always on Top", isOn: $alwaysOnTop)
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 11))
                .onChange(of: alwaysOnTop) { on in
                    menuBar.setWindowLevel(floating: on)
                    infoWindow?.level = on ? .floating : .normal
                }
        }
    }

    // MARK: - Window helpers

    private func openInfoWindow() {
        if infoWindow == nil {
            let vc = NSHostingController(rootView: InfoWindowView(monitor: monitor))
            let win = NSWindow(contentViewController: vc)
            win.title = "Hardware Info"
            win.styleMask = [.titled, .closable, .resizable]
            win.setContentSize(NSSize(width: 420, height: 300))
            win.center()
            win.isRestorable = false
            win.setFrameAutosaveName("")
            let delegate = MinSizeWindowDelegate(minSize: NSSize(width: 380, height: 260))
            win.delegate = delegate
            infoWindowDelegate = delegate
            infoWindow = win
        }
        infoWindow?.level = alwaysOnTop ? .floating : .normal
        infoWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Hardware info window

struct InfoWindowView: View {
    @ObservedObject var monitor: SystemMonitor
    private var soc: MacmonSocInfo? { monitor.socInfo }

    @State private var modelID    = "…"
    @State private var storageFreeGB: Double = 0
    @State private var storageTotalGB: Double = 0
    @State private var storageType = "…"

    private struct Row: Identifiable {
        let name: String; let value: String
        var id: String { name }
    }

    private var rows: [Row] {
        var r: [Row] = []
        r.append(Row(name: "Model",         value: modelID))
        if let s = soc {
            r.append(Row(name: "Chip",       value: s.chipName))
            for tier in s.cpuTiers {
                r.append(Row(name: tier.displayName, value: "\(tier.cores) cores  max \(formatFrequency(s.vm ? nil : tier.maxMHz))"))
            }
            r.append(Row(name: "GPU Cores", value: s.vm ? "Unavailable" : "\(s.gpuCores) cores  max \(formatFrequency(s.gpuMaxMHz))"))
            r.append(Row(name: "Memory",     value: "\(s.memoryGb) GB unified"))
        }
        r.append(Row(name: "Storage Type",  value: storageType))
        r.append(Row(name: "Storage Free",  value: String(format: "%.1f / %.1f GB", storageFreeGB, storageTotalGB)))
        return r
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        HStack {
                            Text(row.name).bold()
                            Spacer()
                            Text(row.value).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .background((idx % 2 == 0) ? Color.gray.opacity(0.08) : Color.clear)
                    }
                }
            }
            .frame(minHeight: 200)
            .textSelection(.enabled)

            Divider()
            Button("Open System Information") {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.SystemProfiler") {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(.vertical, 8)
        }
        .onAppear(perform: loadInfo)
    }

    private func loadInfo() {
        var sz = 0
        sysctlbyname("hw.model", nil, &sz, nil, 0)
        var buf = [CChar](repeating: 0, count: sz)
        sysctlbyname("hw.model", &buf, &sz, nil, 0)
        modelID = String(cString: buf)

        let fm = FileManager.default
        if let attrs = try? fm.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            storageFreeGB  = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            storageFreeGB  /= 1_073_741_824
            storageTotalGB = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
            storageTotalGB /= 1_073_741_824
        }

        DispatchQueue.global(qos: .utility).async {
            let t = Process()
            t.launchPath = "/usr/sbin/diskutil"
            t.arguments = ["info", "-plist", "/"]
            let pipe = Pipe()
            t.standardOutput = pipe
            do {
                try t.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    let type = (plist["SolidState"] as? Bool) == true ? "SSD / NVMe" :
                               (plist["MediumType"] as? String) ?? "Unknown"
                    DispatchQueue.main.async { storageType = type }
                }
            } catch {}
        }
    }
}
