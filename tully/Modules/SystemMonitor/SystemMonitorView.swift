// tully/Modules/SystemMonitor/SystemMonitorView.swift
import SwiftUI

struct SystemMonitorView: View {
    @State private var monitor = SystemMonitorService()
    @State private var diskScanner = DiskScanService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cpuRamSection
                diskSection
                networkSection
                processSection
            }
            .padding(16)
        }
        .onAppear {
            monitor.start()
            diskScanner.scan()
        }
        .onDisappear {
            monitor.stop()
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

            StatRow(
                label: "RAM",
                value: "\(formatBytes(monitor.snapshot.ramUsed)) / \(formatBytes(monitor.snapshot.ramTotal))"
            ) {
                ProgressView(value: monitor.snapshot.ramTotal > 0
                    ? Double(monitor.snapshot.ramUsed) / Double(monitor.snapshot.ramTotal)
                    : 0)
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

            Divider()

            HStack {
                Text("Large Folders")
                    .font(.subheadline).bold()
                Spacer()
                if diskScanner.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    if let date = diskScanner.lastScanDate {
                        Text(date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Rescan") { diskScanner.scan() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            ForEach(diskScanner.topFolders.prefix(10)) { folder in
                HStack {
                    Text(folder.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(formatBytes(folder.bytes))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(folder.url)
                }
            }

            if diskScanner.topFolders.isEmpty && !diskScanner.isScanning {
                Text("No data").foregroundStyle(.secondary).font(.caption)
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

// MARK: - Formatters

private func formatBytes<T: BinaryInteger>(_ bytes: T) -> String {
    let b = Double(bytes)
    if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
    if b >= 1_048_576     { return String(format: "%.1f MB", b / 1_048_576) }
    if b >= 1_024         { return String(format: "%.1f KB", b / 1_024) }
    return "\(bytes) B"
}
