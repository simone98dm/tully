// tully/Modules/DiskUtility/DiskUtilityView.swift
import AppKit
import SwiftUI

struct DiskUtilityView: View {
    @Environment(DiskScanService.self) private var diskScanner

    private let chartColors: [Color] = [
        .blue, .green, .orange, .red, .purple,
        .pink, .yellow, .teal, .indigo, .brown
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                if diskScanner.isScanning && diskScanner.topFolders.isEmpty {
                    scanningPlaceholder
                } else if !diskScanner.topFolders.isEmpty {
                    donutSection
                    Divider()
                    folderListSection
                } else {
                    Text("No data. Tap Refresh to scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                cleanupSection
            }
            .padding(16)
        }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            Label("Large Folders", systemImage: "internaldrive")
                .font(.headline)
            Spacer()
            if diskScanner.isScanning {
                ProgressView().controlSize(.small)
            } else {
                if let date = diskScanner.lastScanDate {
                    Text(date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Refresh") { diskScanner.scan() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var scanningPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                ProgressView()
                Text("Scanning…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 32)
    }

    // MARK: Donut

    @ViewBuilder
    private var donutSection: some View {
        let top10 = Array(diskScanner.topFolders.prefix(10))
        let totalScanned = diskScanner.topFolders.reduce(Int64(0)) { $0 + $1.bytes }
        let othersBytes = max(0, totalScanned - top10.reduce(Int64(0)) { $0 + $1.bytes })

        HStack(alignment: .top, spacing: 12) {
            DonutChart(
                segments: top10,
                othersBytes: othersBytes,
                total: totalScanned,
                colors: chartColors
            )
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(top10.indices, id: \.self) { i in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(chartColors[i % chartColors.count])
                            .frame(width: 8, height: 8)
                        Text(top10[i].name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(fmtBytes(top10[i].bytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if othersBytes > 0 {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary)
                            .frame(width: 8, height: 8)
                        Text("Others").font(.caption)
                        Spacer()
                        Text(fmtBytes(othersBytes))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Folder List

    private var folderListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diskScanner.topFolders.prefix(10)) { folder in
                HStack(spacing: 8) {
                    Text(folder.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(fmtBytes(folder.bytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { NSWorkspace.shared.open(folder.url) }
                .padding(.vertical, 5)
                Divider()
            }
        }
    }

    // MARK: Cleanup

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cleanup", systemImage: "wand.and.sparkles")
                .font(.headline)
            Text("Uses mole (mo) to clean caches and optimize the system.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { runMoleClean() } label: {
                Label("Cleanup with mole", systemImage: "trash.slash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: Helpers

    private func fmtBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func runMoleClean() {
        let moPaths = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo"]
        guard moPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) else {
            let alert = NSAlert()
            alert.messageText = "mole not installed"
            alert.informativeText = "Install it with Homebrew:\nbrew install tw93/mole/mole\n\nThen relaunch tully."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        let src = """
            tell application "Terminal"
                activate
                do script "mo clean"
            end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if err != nil {
            let alert = NSAlert()
            alert.messageText = "Could not open Terminal"
            alert.informativeText = "Run manually in Terminal:\nmo clean"
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - DonutChart

private struct DonutChart: View {
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
                let fraction = Double(bytes) / Double(total)
                let end = start + fraction * 2 * .pi
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + outerR * cos(start),
                    y: center.y + outerR * sin(start)
                ))
                path.addArc(center: center, radius: outerR,
                            startAngle: .radians(start), endAngle: .radians(end),
                            clockwise: false)
                path.addArc(center: center, radius: innerR,
                            startAngle: .radians(end), endAngle: .radians(start),
                            clockwise: true)
                path.closeSubpath()
                ctx.fill(path, with: .color(color))
                ctx.stroke(path, with: .color(.white.opacity(0.25)), lineWidth: 1)
                start = end
            }
        }
    }
}
