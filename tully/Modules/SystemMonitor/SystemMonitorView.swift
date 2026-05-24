// tully/Modules/SystemMonitor/SystemMonitorView.swift
import SwiftUI

struct SystemMonitorView: View {
    @Environment(SystemMonitorService.self) private var monitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if monitor.snapshot.battery.isPresent {
                    batterySection
                }
                cpuRamSection
                diskSection
                networkSection
                processSection
            }
            .padding(16)
        }
    }

    // MARK: Battery

    private var batterySection: some View {
        let b = monitor.snapshot.battery
        let pct = Double(b.percentage) / 100.0
        let tint: Color = b.percentage > 20 ? .green : .red
        let statusText: String = {
            if b.isCharged { return "Charged" }
            if b.isCharging {
                return b.timeRemaining > 0 ? "Charging · \(formatMinutes(b.timeRemaining))" : "Charging…"
            }
            return b.timeRemaining > 0 ? "\(formatMinutes(b.timeRemaining)) remaining" : "On Battery"
        }()
        return VStack(alignment: .leading, spacing: 8) {
            Label("Battery", systemImage: b.isCharging ? "battery.100.bolt" : "battery.100")
                .font(.headline)
            StatRow(label: "\(b.percentage)%  \(statusText)", value: b.cycleCount > 0 ? "\(b.cycleCount) cycles" : "") {
                ProgressView(value: pct).tint(tint)
            }
        }
    }

    // MARK: CPU + RAM

    private var cpuRamSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("CPU & Memory", systemImage: "cpu")
                .font(.headline)

            StatRow(label: "CPU", value: String(format: "%.1f%%", monitor.snapshot.cpuPercent)) {
                ProgressView(value: monitor.snapshot.cpuPercent / 100.0)
                    .tint(monitor.snapshot.cpuPercent > 80 ? .red : .blue)
            }

            let snap = monitor.snapshot
            let ramRatio = snap.ramTotal > 0 ? Double(snap.ramUsed) / Double(snap.ramTotal) : 0
            StatRow(
                label: "RAM",
                value: "\(formatBytes(snap.ramUsed)) / \(formatBytes(snap.ramTotal))"
            ) {
                ProgressView(value: ramRatio)
                    .tint(ramRatio > 0.85 ? .red : ramRatio > 0.65 ? .orange : .blue)
            }

            if snap.ramTotal > 0 {
                HStack(spacing: 12) {
                    MemChip(label: "Wired", bytes: snap.ramWired, color: .red)
                    MemChip(label: "Compressed", bytes: snap.ramCompressed, color: .purple)
                    MemChip(label: "Free", bytes: snap.ramTotal > snap.ramUsed ? snap.ramTotal - snap.ramUsed : 0, color: .green)
                }
            }
        }
    }

    // MARK: Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Disk", systemImage: "internaldrive")
                .font(.headline)

            StatRow(
                label: "Storage",
                value: "\(formatBytes(monitor.snapshot.diskUsed)) / \(formatBytes(monitor.snapshot.diskTotal))"
            ) {
                ProgressView(value: monitor.snapshot.diskTotal > 0
                    ? Double(monitor.snapshot.diskUsed) / Double(monitor.snapshot.diskTotal)
                    : 0)
            }
        }
    }

    // MARK: Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network", systemImage: "network")
                .font(.headline)
            HStack {
                Label("↓ \(formatBytes(Int64(max(0, monitor.snapshot.netIn))))/s", systemImage: "arrow.down")
                Spacer()
                Label("↑ \(formatBytes(Int64(max(0, monitor.snapshot.netOut))))/s", systemImage: "arrow.up")
            }
            .font(.subheadline)

            if !monitor.snapshot.topNet.isEmpty {
                Text("Active connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(monitor.snapshot.topNet) { proc in
                    HStack {
                        Text(proc.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(proc.connections) sockets")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Top Processes", systemImage: "list.bullet")
                .font(.headline)

            Text("By CPU").font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.snapshot.topCPU) { proc in
                ProcessRow(info: proc, metric: String(format: "%.1f%%", proc.cpuPercent))
            }

            Divider()

            Text("By RAM").font(.caption).foregroundStyle(.secondary)
            ForEach(monitor.snapshot.topRAM) { proc in
                ProcessRow(info: proc, metric: formatBytes(proc.ramBytes))
            }
        }
    }
}

// MARK: - Subviews

private struct StatRow<Progress: View>: View {
    let label: String
    let value: String
    @ViewBuilder let progress: () -> Progress

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption.monospacedDigit())
            }
            progress()
        }
    }
}

private struct ProcessRow: View {
    let info: ProcessInfo
    let metric: String

    var body: some View {
        HStack {
            Text(info.name).lineLimit(1).font(.caption)
            Spacer()
            Text(metric).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct MemChip: View {
    let label: String
    let bytes: UInt64
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(formatBytes(bytes)).font(.system(size: 9).monospacedDigit())
        }
    }
}

// MARK: - Formatters

private func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}

private func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
    let b = Double(bytes)
    if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
    if b >= 1_048_576     { return String(format: "%.1f MB", b / 1_048_576) }
    if b >= 1_024         { return String(format: "%.1f KB", b / 1_024) }
    return "\(bytes) B"
}
