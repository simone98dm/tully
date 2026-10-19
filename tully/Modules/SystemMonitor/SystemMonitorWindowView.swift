import AppKit
import SwiftUI

/// Full system monitor window: usage history plus processes grouped under their app.
struct SystemMonitorWindowView: View {
    private enum SortKey: String, CaseIterable { case cpu = "CPU", memory = "Memory" }

    private enum RowID: Hashable {
        case group(String)
        case process(Int32)
    }

    @Environment(SystemMonitorService.self) private var monitor
    @Environment(ToastCenter.self) private var toasts

    @State private var query = ""
    @State private var sortKey: SortKey = .cpu
    @State private var expanded: Set<String> = []
    @State private var selection: RowID?
    @State private var detailProcess: ProcessInfo?
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isListFocused: Bool

    private let coreCount = Double(Foundation.ProcessInfo.processInfo.activeProcessorCount)

    var body: some View {
        VStack(spacing: 16) {
            historyCards
            toolbar
            processList
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 640)
        .toastOverlay()
        .background {
            // ⌘F focuses search
            Button("") { isSearchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        }
        .sheet(item: $detailProcess) { process in
            ProcessDetailView(process: process, coreCount: coreCount) { message, isError in
                toasts.show(message, style: isError ? .error : .success)
            }
        }
        .onAppear { isListFocused = true }
    }

    // MARK: History

    private var historyCards: some View {
        let snap = monitor.snapshot
        let history = monitor.history
        let memoryRatio = snap.ramTotal > 0 ? Double(snap.ramUsed) / Double(snap.ramTotal) : 0
        let diskRatio = snap.diskTotal > 0 ? Double(snap.diskUsed) / Double(snap.diskTotal) : 0
        let netPeak = max(history.map { max($0.netIn, $0.netOut) }.max() ?? 0, 1024)

        let sensors = snap.sensors

        return VStack(spacing: 10) {
            HStack(spacing: 12) {
            HistoryCard(title: "CPU", value: String(format: "%.1f%%", snap.cpuPercent),
                        detail: "\(Int(coreCount)) cores" + (sensors.cpuTemperature.map { " · " + formatTemperature($0) } ?? ""),
                        tint: .mint, series: [history.map(\.cpu)])
            HistoryCard(title: "GPU", value: sensors.gpuPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                        detail: sensors.gpuTemperature.map(formatTemperature) ?? "Utilisation",
                        tint: .pink, series: [history.map(\.gpu)])
            HistoryCard(title: "Memory", value: String(format: "%.0f%%", memoryRatio * 100),
                        detail: "\(formatBytes(snap.ramUsed)) of \(formatBytes(snap.ramTotal)) · wired \(formatBytes(snap.ramWired)) · compressed \(formatBytes(snap.ramCompressed))", tint: .blue,
                        series: [history.map(\.memory)])
            HistoryCard(title: "Network", value: "↓ \(formatRate(snap.netIn))",
                        detail: "↑ \(formatRate(snap.netOut)) · \(monitor.localIP)", tint: .orange,
                        series: [history.map { $0.netIn / netPeak }, history.map { $0.netOut / netPeak }])
            HistoryCard(title: "Disk", value: String(format: "%.0f%%", diskRatio * 100),
                        detail: "\(formatBytes(max(0, snap.diskTotal - snap.diskUsed), style: .file)) free", tint: .purple,
                        series: [], gauge: diskRatio)
            }
            sensorStrip(sensors)
        }
    }

    @ViewBuilder
    private func sensorStrip(_ sensors: SensorReadings) -> some View {
        let parts = [
            sensors.cpuTemperature.map { "CPU \(formatTemperature($0))" },
            sensors.gpuTemperature.map { "GPU \(formatTemperature($0))" },
            sensors.fanRPMs.isEmpty ? nil
                : sensors.fanRPMs.allSatisfy { $0 < 1 } ? "Fans idle"
                : "Fans " + sensors.fanRPMs.map { $0.formatted(.number.precision(.fractionLength(0))) }.joined(separator: " / ") + " rpm",
        ].compactMap { $0 }
        if !parts.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                Text(parts.joined(separator: "  ·  "))
                Spacer()
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search processes", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { isListFocused = true }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.tullyIcon)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .glassEffect(.regular, in: .capsule)

            Picker("Sort by", selection: $sortKey) {
                ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }
    }

    // MARK: Process list

    private var sortedGroups: [ProcessGroup] {
        let groups = monitor.groups.compactMap { group -> ProcessGroup? in
            guard !query.isEmpty else { return group }
            if group.name.localizedCaseInsensitiveContains(query) { return group }
            let members = group.members.filter { $0.name.localizedCaseInsensitiveContains(query) }
            guard !members.isEmpty else { return nil }
            return ProcessGroup(id: group.id, name: group.name, rootPID: group.rootPID, iconPath: group.iconPath, members: members,
                                cpuPercent: group.cpuPercent, ramBytes: group.ramBytes)
        }
        return groups.sorted {
            sortKey == .cpu ? $0.cpuPercent > $1.cpuPercent : $0.ramBytes > $1.ramBytes
        }
    }

    private func isExpanded(_ group: ProcessGroup) -> Bool {
        expanded.contains(group.id) || (!query.isEmpty && !group.name.localizedCaseInsensitiveContains(query))
    }

    private var processList: some View {
        let groups = sortedGroups
        let rows = groups.flatMap { group in
            [RowID.group(group.id)] + (isExpanded(group) ? group.members.map { RowID.process($0.pid) } : [])
        }

        return VStack(spacing: 0) {
            HStack {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("CPU").frame(width: 170, alignment: .leading)
                Text("Memory").frame(width: 170, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(groups) { group in
                            groupRow(group)
                            if isExpanded(group) {
                                ForEach(group.members) { memberRow($0) }
                            }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, row in
                    if let row { proxy.scrollTo(row) }
                }
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { move(by: 1, in: rows); return .handled }
            .onKeyPress(.upArrow) { move(by: -1, in: rows); return .handled }
            .onKeyPress(.rightArrow) { setExpanded(true, groups: groups); return .handled }
            .onKeyPress(.leftArrow) { setExpanded(false, groups: groups); return .handled }
            .onKeyPress(.return) { openSelection(groups: groups); return .handled }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func groupRow(_ group: ProcessGroup) -> some View {
        let isSelected = selection == .group(group.id)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .rotationEffect(.degrees(isExpanded(group) ? 90 : 0))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            groupIcon(group)
            Text(group.name).lineLimit(1)
            Text(verbatim: "\(group.members.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .background(.quaternary, in: Capsule())
            Spacer(minLength: 8)
            metric(fraction: group.cpuPercent / (100 * coreCount), text: String(format: "%.1f%%", group.cpuPercent), tint: .mint)
            metric(fraction: memoryFraction(group.ramBytes), text: formatBytes(group.ramBytes), tint: .blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .id(RowID.group(group.id))
        .pointerStyle(.link)
        .onTapGesture { toggleGroup(group) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.name), \(group.members.count) processes")
        .accessibilityValue(String(format: "CPU %.1f percent, memory %@", group.cpuPercent, formatBytes(group.ramBytes)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(isExpanded(group) ? "Collapses the group" : "Shows its processes")
        .accessibilityAction { toggleGroup(group) }
    }

    private func memberRow(_ process: ProcessInfo) -> some View {
        let isSelected = selection == .process(process.pid)
        return HStack(spacing: 8) {
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Text(verbatim: "\(process.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            metric(fraction: process.cpuPercent / (100 * coreCount), text: String(format: "%.1f%%", process.cpuPercent), tint: .mint)
            metric(fraction: memoryFraction(process.ramBytes), text: formatBytes(process.ramBytes), tint: .blue)
        }
        .font(.callout)
        .padding(.leading, 52)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .id(RowID.process(process.pid))
        .pointerStyle(.link)
        .onTapGesture(count: 2) { detailProcess = process }
        .onTapGesture {
            selection = .process(process.pid)
            isListFocused = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(process.name), process \(process.pid)")
        .accessibilityValue(String(format: "CPU %.1f percent, memory %@", process.cpuPercent, formatBytes(process.ramBytes)))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Shows details")
        .accessibilityAction { detailProcess = process }
    }

    private func toggleGroup(_ group: ProcessGroup) {
        selection = .group(group.id)
        isListFocused = true
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }

    @ViewBuilder
    private func groupIcon(_ group: ProcessGroup) -> some View {
        if let path = group.iconPath {
            Image(nsImage: IconCache.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "gearshape.2.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    private func metric(fraction: Double, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            UsageBar(fraction: fraction, tint: tint)
                .frame(width: 90)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .frame(width: 170, alignment: .leading)
    }

    private func memoryFraction(_ bytes: UInt64) -> Double {
        monitor.snapshot.ramTotal > 0 ? Double(bytes) / Double(monitor.snapshot.ramTotal) : 0
    }

    // MARK: Keyboard

    private func move(by delta: Int, in rows: [RowID]) {
        guard !rows.isEmpty else { return }
        let current = selection.flatMap { rows.firstIndex(of: $0) } ?? (delta > 0 ? -1 : rows.count)
        selection = rows[min(max(0, current + delta), rows.count - 1)]
    }

    private func setExpanded(_ value: Bool, groups: [ProcessGroup]) {
        switch selection {
        case .group(let id):
            if value { expanded.insert(id) } else { expanded.remove(id) }
        case .process(let pid) where !value:
            // ← on a child jumps back to its group
            if let group = groups.first(where: { $0.members.contains { $0.pid == pid } }) {
                expanded.remove(group.id)
                selection = .group(group.id)
            }
        default:
            break
        }
    }

    private func openSelection(groups: [ProcessGroup]) {
        switch selection {
        case .group(let id):
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        case .process(let pid):
            detailProcess = groups.lazy.flatMap(\.members).first { $0.pid == pid }
        case nil:
            break
        }
    }
}

// MARK: - History card

private struct HistoryCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let series: [[Double]]
    var gauge: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Group {
                if let gauge {
                    UsageBar(fraction: gauge, tint: tint).padding(.top, 20)
                } else {
                    ZStack {
                        ForEach(series.indices, id: \.self) { index in
                            AreaSparkline(values: series[index])
                                .fill(LinearGradient(colors: [seriesColor(index).opacity(0.45), seriesColor(index).opacity(0.02)],
                                                     startPoint: .top, endPoint: .bottom))
                            AreaSparkline(values: series[index], closed: false)
                                .stroke(seriesColor(index), lineWidth: 1.5)
                        }
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func seriesColor(_ index: Int) -> Color { index == 0 ? tint : .blue }
}

/// Line (or filled area) through values in 0…1, oldest on the left.
private struct AreaSparkline: Shape {
    let values: [Double]
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        func point(_ index: Int) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(index) * step,
                    y: rect.maxY - rect.height * CGFloat(min(1, max(0, values[index]))))
        }
        path.move(to: point(0))
        for index in 1..<values.count { path.addLine(to: point(index)) }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Process detail

private struct ProcessDetailView: View {
    let process: ProcessInfo
    let coreCount: Double
    let report: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForceQuit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: IconCache.icon(forFile: process.path.isEmpty ? "/bin/sh" : process.path))
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text(process.name).font(.title3.weight(.semibold))
                    Text(process.isSystem ? "System process" : "User process")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("PID", String(process.pid))
                row("Parent PID", String(process.parentPID))
                row("CPU", String(format: "%.1f%%", process.cpuPercent))
                row("Memory", formatBytes(process.ramBytes))
                row("Path", process.path.isEmpty ? "—" : process.path)
            }

            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
                }
                .disabled(process.path.isEmpty)
                Spacer()
                Button("Quit") { terminate(force: false) }
                    .disabled(!ProcessTerminator.canTerminate(process.pid))
                Button("Force Quit…", role: .destructive) { confirmForceQuit = true }
                    .disabled(!ProcessTerminator.canTerminate(process.pid))
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog("Force quit \(process.name)?", isPresented: $confirmForceQuit, titleVisibility: .visible) {
            Button("Force Quit", role: .destructive) { terminate(force: true) }
        } message: {
            Text("Unsaved changes will be lost.")
        }
    }

    private func terminate(force: Bool) {
        switch ProcessTerminator.terminate(pid: process.pid, name: process.name, force: force, expectedPath: process.path) {
        case .terminated: report(force ? "Force quit \(process.name)" : "Asked \(process.name) to quit", false)
        case .refused(let message), .failed(let message): report(message, true)
        }
        dismiss()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
        }
    }
}
