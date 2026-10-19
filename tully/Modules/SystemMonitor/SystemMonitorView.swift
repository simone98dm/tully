import AppKit
import SwiftUI

/// Popover System tab: usage rings, network, top processes.
struct SystemMonitorView: View {
    @Environment(SystemMonitorService.self) private var monitor
    @Environment(PopoverState.self) private var popover
    @Environment(ToastCenter.self) private var toasts
    @State private var processToKill: ProcessInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ringSection
                Divider()
                networkSection
                Divider()
                processSection
            }
            .padding(16)
        }
        .confirmationDialog(
            "Quit \(processToKill?.name ?? "process")?",
            isPresented: Binding(get: { processToKill != nil }, set: { if !$0 { processToKill = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quit", role: .destructive) {
                if let process = processToKill { terminate(process) }
                processToKill = nil
            }
            Button("Cancel", role: .cancel) { processToKill = nil }
        } message: {
            Text("Asks the process to quit (SIGTERM). Unsaved work in it may be lost.")
        }
    }

    // MARK: Rings

    private var ringSection: some View {
        let snap = monitor.snapshot

        return HStack(spacing: 0) {
            UsageRing(fraction: snap.cpuPercent / 100, label: "CPU", symbol: "cpu",
                      detail: String(format: "%.1f%% of all cores", snap.cpuPercent)
                        + (snap.sensors.cpuTemperature.map { " · \(formatTemperature($0))" } ?? "")) {
                popover.open(.systemMonitor)
            }
            UsageRing(fraction: snap.ramFraction, label: "Memory", symbol: "memorychip",
                      detail: "\(formatBytes(snap.ramUsed)) of \(formatBytes(snap.ramTotal)) used · "
                        + "wired \(formatBytes(snap.ramWired)) · compressed \(formatBytes(snap.ramCompressed))") {
                popover.open(.systemMonitor)
            }
            UsageRing(fraction: snap.diskFraction, label: "Disk", symbol: "internaldrive",
                      detail: snap.diskTotal > 0
                        ? "\(formatBytes(snap.diskUsed, style: .file)) of \(formatBytes(snap.diskTotal, style: .file)) used"
                        : "Measuring…") {
                popover.select(.disk)
            }
        }
    }

    // MARK: Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network", systemImage: "network").font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    Label(formatRate(monitor.snapshot.netIn), systemImage: "arrow.down")
                        .foregroundStyle(Theme.download)
                        .accessibilityLabel("Download \(formatRate(monitor.snapshot.netIn))")
                    Label(formatRate(monitor.snapshot.netOut), systemImage: "arrow.up")
                        .foregroundStyle(Theme.upload)
                        .accessibilityLabel("Upload \(formatRate(monitor.snapshot.netOut))")
                }
                .font(.caption.monospacedDigit())
            }

            if monitor.history.count > 1 {
                SparklineView(history: monitor.history.suffix(30).map { ($0.netIn, $0.netOut) })
                    .accessibilityLabel("Network activity over the last minute")
            }

            Label(monitor.localIP, systemImage: "wifi")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Local IP address \(monitor.localIP)")
                .textSelection(.enabled)
        }
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Top Memory", systemImage: "list.bullet").font(.headline)
                Spacer()
                Button { popover.open(.systemMonitor) } label: {
                    Label("All Processes", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.tully)
                .font(.caption)
                .accessibilityHint("Opens the System Monitor window")
            }
            HStack {
                Text("App").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 52, alignment: .trailing)
                Text("Memory").frame(width: 70, alignment: .trailing)
                Spacer().frame(width: 26)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            let groups = monitor.topGroupsByMemory(5)
            if groups.isEmpty {
                EmptyStateView(symbol: "hourglass", message: "Collecting process data…")
            }
            ForEach(groups) { group in
                GroupRow(group: group) {
                    // quitting a group means quitting its app process, not a helper
                    processToKill = monitor.snapshot.processes.first { $0.pid == group.rootPID } ?? group.members.first
                }
            }
        }
    }

    private func terminate(_ process: ProcessInfo) {
        switch ProcessTerminator.terminate(pid: process.pid, name: process.name, expectedPath: process.path) {
        case .terminated: toasts.show("Asked \(process.name) to quit")
        case .refused(let message), .failed(let message): toasts.show(message, style: .error)
        }
    }
}

// MARK: - SparklineView

struct SparklineView: View {
    let history: [(netIn: Double, netOut: Double)]

    var body: some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let maxVal = max(history.flatMap { [$0.netIn, $0.netOut] }.max() ?? 0, 1024.0)
            let n = history.count

            func point(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1), y: size.height * CGFloat(1 - v / maxVal))
            }
            func line(_ value: (Int) -> Double) -> Path {
                var path = Path()
                path.move(to: point(0, value(0)))
                for i in 1..<n { path.addLine(to: point(i, value(i))) }
                return path
            }
            let style = StrokeStyle(lineWidth: 1.5, lineJoin: .round)
            ctx.stroke(line { history[$0].netIn }, with: .color(Theme.download), style: style)
            // upload dashed so the two series differ without colour
            ctx.stroke(line { history[$0].netOut }, with: .color(Theme.upload),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [3, 2]))
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(height: 48)
    }
}

// MARK: - ProcessRow

private struct GroupRow: View {
    let group: ProcessGroup
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let path = group.iconPath {
                Image(nsImage: IconCache.icon(forFile: path))
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(group.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "%.0f%%", group.cpuPercent))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text(formatBytes(group.ramBytes))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Button(action: onQuit) {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.tullyIcon)
            .frame(width: 26)
            .disabled(group.isSystem)
            .accessibilityLabel("Quit \(group.name)")
            .help(group.isSystem ? "System processes can't be quit here" : "Quit \(group.name)")
        }
        .font(.caption.monospacedDigit())
        .padding(.vertical, 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.name), \(formatBytes(group.ramBytes))")
    }
}
