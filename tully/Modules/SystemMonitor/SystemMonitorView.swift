// tully/Modules/SystemMonitor/SystemMonitorView.swift
import AppKit
import Darwin
import SwiftUI

struct SystemMonitorView: View {
    @Environment(SystemMonitorService.self) private var monitor
    @State private var processToKill: ProcessInfo? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ringSection
                Divider()
                networkSection
                Divider()
                processSection
            }
            .padding(16)
        }
        .confirmationDialog(
            "Kill \(processToKill?.name ?? "process")?",
            isPresented: Binding(get: { processToKill != nil }, set: { if !$0 { processToKill = nil } }),
            titleVisibility: .visible
        ) {
            Button("Kill", role: .destructive) {
                if let proc = processToKill { Darwin.kill(proc.pid, SIGTERM) }
                processToKill = nil
            }
            Button("Cancel", role: .cancel) { processToKill = nil }
        } message: {
            Text("Sends SIGTERM to the process.")
        }
    }

    // MARK: Ring Gauges

    private var ringSection: some View {
        let snap = monitor.snapshot
        let cpuVal = snap.cpuPercent / 100
        let cpuColor: Color = snap.cpuPercent >= 80 ? .red : .blue
        let cpuTooltip = String(format: "%.1f%% / 100%%", snap.cpuPercent)

        let ramRatio = snap.ramTotal > 0 ? Double(snap.ramUsed) / Double(snap.ramTotal) : 0
        let ramColor: Color = ramRatio > 0.85 ? .red : ramRatio > 0.65 ? .orange : .blue
        let ramTooltip = "\(formatBytes(snap.ramUsed)) / \(formatBytes(snap.ramTotal))"

        return HStack(spacing: 0) {
            RingGauge(value: cpuVal, color: cpuColor, label: "CPU", tooltip: cpuTooltip)
                .frame(maxWidth: .infinity)
            RingGauge(value: ramRatio, color: ramColor, label: "RAM", tooltip: ramTooltip)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Network", systemImage: "network")
                    .font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    Label(formatBytes(Int64(max(0, monitor.snapshot.netIn))) + "/s",
                          systemImage: "arrow.down")
                        .foregroundStyle(.blue)
                    Label(formatBytes(Int64(max(0, monitor.snapshot.netOut))) + "/s",
                          systemImage: "arrow.up")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }

            if monitor.networkHistory.count > 1 {
                SparklineView(history: monitor.networkHistory)
            }

            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(monitor.localIP)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Processes", systemImage: "list.bullet")
                .font(.headline)

            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("PID").frame(width: 52, alignment: .trailing)
                Text("RAM").frame(width: 64, alignment: .trailing)
                Spacer().frame(width: 28)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            ForEach(monitor.snapshot.topRAM) { proc in
                ProcessKillRow(info: proc) { processToKill = proc }
            }
        }
    }
}

// MARK: - RingGauge

private struct RingGauge: View {
    let value: Double   // 0–1
    let color: Color
    let label: String
    let tooltip: String

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) / 2 - 8
                    let lw: CGFloat = 10

                    var track = Path()
                    track.addArc(center: center, radius: radius,
                                 startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
                    ctx.stroke(track, with: .color(.secondary.opacity(0.15)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))

                    guard value > 0 else { return }
                    var arc = Path()
                    arc.addArc(center: center, radius: radius,
                               startAngle: .degrees(-90), endAngle: .degrees(-90 + value * 360),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(color),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
                .frame(width: 90, height: 90)

                Text(String(format: "%.0f%%", value * 100))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(tooltip)
    }
}

// MARK: - SparklineView

private struct SparklineView: View {
    let history: [(netIn: Double, netOut: Double)]

    var body: some View {
        Canvas { ctx, size in
            guard history.count > 1 else { return }
            let maxVal = max(history.flatMap { [$0.netIn, $0.netOut] }.max() ?? 0, 1024.0)
            let n = history.count

            func pt(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(
                    x: size.width * CGFloat(i) / CGFloat(n - 1),
                    y: size.height * CGFloat(1 - v / maxVal)
                )
            }

            var down = Path()
            down.move(to: pt(0, history[0].netIn))
            for i in 1..<n { down.addLine(to: pt(i, history[i].netIn)) }
            ctx.stroke(down, with: .color(.blue.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            var up = Path()
            up.move(to: pt(0, history[0].netOut))
            for i in 1..<n { up.addLine(to: pt(i, history[i].netOut)) }
            ctx.stroke(up, with: .color(.orange.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(height: 48)
    }
}

// MARK: - ProcessKillRow

private struct ProcessKillRow: View {
    let info: ProcessInfo
    let onKill: () -> Void

    var body: some View {
        HStack {
            Text(info.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(info.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)

            Text(formatBytes(info.ramBytes))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            Button(action: onKill) {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .frame(width: 28)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Formatters

private func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
    let b = Double(bytes)
    if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
    if b >= 1_048_576     { return String(format: "%.1f MB", b / 1_048_576) }
    if b >= 1_024         { return String(format: "%.1f KB", b / 1_024) }
    return "\(bytes) B"
}
