import AppKit
import SwiftUI

struct DiskUtilityView: View {
    @Environment(DiskScanService.self) private var diskScanner
    @Environment(PopoverState.self) private var popover

    static let chartColors: [Color] = [
        .blue, .green, .orange, .red, .purple,
        .pink, .yellow, .teal, .indigo, .brown,
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "Large Folders", symbol: "internaldrive",
                          subtitle: subtitle) { headerAccessory }
                    .padding(.horizontal, -16)
                if diskScanner.isScanning && diskScanner.topFolders.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", message: "Scanning your home folder…")
                } else if !diskScanner.topFolders.isEmpty {
                    donutSection
                    Divider()
                    folderListSection
                } else {
                    EmptyStateView(symbol: "chart.pie", message: "See which folders in your home take the most space.",
                                   actionTitle: "Scan Home Folder") { diskScanner.scan() }
                }
                cleanUpButton
            }
            .padding(16)
        }
    }

    private var cleanUpButton: some View {
        Button { popover.open(.diskClean) } label: {
            Label("Clean Up…", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .pointerStyle(.link)
        .accessibilityHint("Opens Disk Clean to free space by moving caches, logs and more to the Trash")
    }

    private var subtitle: String? {
        guard let date = diskScanner.lastScanDate else { return nil }
        return "Scanned at \(date.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var headerAccessory: some View {
        if diskScanner.isScanning {
            ProgressView().controlSize(.small).accessibilityLabel("Scanning")
        } else if diskScanner.lastScanDate != nil {
            Button { diskScanner.scan() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.tully)
            .accessibilityHint("Measures the folders again")
        }
    }

    // MARK: Donut

    @ViewBuilder
    private var donutSection: some View {
        let top10 = Array(diskScanner.topFolders.prefix(10))
        let totalScanned = diskScanner.topFolders.reduce(Int64(0)) { $0 + $1.bytes }
        let othersBytes = max(0, totalScanned - top10.reduce(Int64(0)) { $0 + $1.bytes })

        HStack(alignment: .top, spacing: 12) {
            Button { popover.open(.diskClean) } label: {
                DonutChart(segments: top10, othersBytes: othersBytes, total: totalScanned, colors: Self.chartColors)
                    .frame(width: 110, height: 110)
            }
            .buttonStyle(.tully)
            .accessibilityLabel("Space used by \(top10.count) largest folders, \(formatBytes(totalScanned, style: .file)) in total")
            .accessibilityHint("Opens Disk Clean")
            .help("Open Disk Clean")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(top10.indices, id: \.self) { i in
                    legendRow(color: Self.chartColors[i % Self.chartColors.count], name: top10[i].name, bytes: top10[i].bytes)
                }
                if othersBytes > 0 {
                    legendRow(color: .secondary, name: "Others", bytes: othersBytes)
                }
            }
            .accessibilityHidden(true) // same data as the list below
        }
    }

    private func legendRow(color: Color, name: String, bytes: Int64) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(name).font(.caption).lineLimit(1)
            Spacer()
            Text(formatBytes(bytes, style: .file))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Folder list

    private var folderListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diskScanner.topFolders.prefix(10)) { folder in
                Button { popover.open(.diskClean) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(folder.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(formatBytes(folder.bytes, style: .file))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .buttonStyle(.tullyRow)
                .accessibilityLabel("\(folder.name), \(formatBytes(folder.bytes, style: .file))")
                .accessibilityHint("Opens Disk Clean. More actions in the context menu")
                .help("Open Disk Clean · right-click to show in Finder")
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                    Button("Open Disk Clean…") { popover.open(.diskClean) }
                }
            }
        }
        .padding(.horizontal, -8)
    }
}

// MARK: - DonutChart

struct DonutChart: View {
    let segments: [FolderInfo]
    let othersBytes: Int64
    let total: Int64
    let colors: [Color]

    var body: some View {
        Canvas { ctx, size in
            guard total > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) / 2 - 2
            let innerR = outerR * 0.52
            var start = -Double.pi / 2

            var all: [(bytes: Int64, color: Color)] = segments.enumerated().map { i, f in
                (f.bytes, colors[i % colors.count])
            }
            if othersBytes > 0 { all.append((othersBytes, .gray)) }

            for (bytes, color) in all {
                let end = start + Double(bytes) / Double(total) * 2 * .pi
                var path = Path()
                path.addArc(center: center, radius: outerR, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
                path.addArc(center: center, radius: innerR, startAngle: .radians(end), endAngle: .radians(start), clockwise: true)
                path.closeSubpath()
                ctx.fill(path, with: .color(color))
                ctx.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 1)
                start = end
            }
        }
    }
}
