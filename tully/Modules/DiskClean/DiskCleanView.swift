import AppKit
import SwiftUI

/// Disk Clean window: scan, pick targets (and single items), confirm, move to the Trash.
struct DiskCleanView: View {
    @Environment(DiskCleanService.self) private var diskClean
    @Environment(SystemMonitorService.self) private var monitor
    @Environment(ToastCenter.self) private var toasts

    @State private var showConfirmation = false
    @State private var showAddTarget = false
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section {
                    ForEach(diskClean.allTargets) { targetRow($0) }
                } header: {
                    HStack {
                        Text("What to clean")
                        Spacer()
                        Button { showAddTarget = true } label: { Label("Add Target", systemImage: "plus") }
                            .buttonStyle(.tully)
                    }
                } footer: {
                    Text("Items are moved to the Trash, so you can put them back. Apps rebuild their caches when needed. The Trash target empties the Trash permanently.")
                }

                if !diskClean.unscannable.isEmpty {
                    Section("Couldn't read") {
                        ForEach(diskClean.unscannable, id: \.self) { Text($0).font(.callout.monospaced()) }
                        PermissionStatusRow(title: "Full Disk Access", detail: "Needed for protected folders such as the Trash",
                                            isGranted: false, pane: .fullDiskAccess)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 640, minHeight: 520)
        .toastOverlay()
        .onAppear { if diskClean.scans.isEmpty { diskClean.scan() } }
        .sheet(isPresented: $showAddTarget) { AddCleanTargetSheet() }
        .sheet(isPresented: $showConfirmation) { CleanConfirmationSheet(onConfirm: clean) }
    }

    // MARK: Header

    private var header: some View {
        let snap = monitor.snapshot
        let free = max(0, snap.diskTotal - snap.diskUsed)
        return HStack(spacing: 16) {
            UsageRing(fraction: snap.diskFraction, label: "Disk", symbol: "internaldrive",
                      detail: "\(formatBytes(free, style: .file)) available", size: 56)
                .frame(width: 80)
            VStack(alignment: .leading, spacing: 4) {
                Text(formatBytes(diskClean.selectedBytes, style: .file))
                    .font(.title.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("\(formatBytes(diskClean.selectedBytes, style: .file)) selected")
                Text(statusText(free: free))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if diskClean.isScanning || diskClean.isCleaning {
                ProgressView().controlSize(.small).accessibilityLabel(diskClean.isCleaning ? "Cleaning" : "Scanning")
            }
            Button { diskClean.scan() } label: { Label("Scan", systemImage: "arrow.clockwise") }
                .disabled(diskClean.isScanning || diskClean.isCleaning)
                .pointerStyle(.link)
            Button { showConfirmation = true } label: { Label("Move to Trash…", systemImage: "trash") }
                .buttonStyle(.borderedProminent)
                .disabled(diskClean.isScanning || diskClean.isCleaning || diskClean.selectedItems.isEmpty)
                .pointerStyle(.link)
        }
        .padding(20)
    }

    private func statusText(free: Int64) -> String {
        if diskClean.isCleaning { return "Moving items to the Trash…" }
        if diskClean.isScanning { return "Scanning…" }
        let available = "\(formatBytes(free, style: .file)) available"
        if let result = diskClean.lastResult {
            return "Cleaned \(formatBytes(result.freedBytes, style: .file)) · \(available)"
        }
        return "selected to clean · \(available)"
    }

    // MARK: Targets

    private func targetRow(_ target: CleanTarget) -> some View {
        let scan = diskClean.scans[target.id]
        let isExpanded = expanded.contains(target.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { diskClean.isSelected(target) },
                                     set: { diskClean.setSelected($0, for: target) })) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Clean \(target.name)")

                Image(systemName: target.category.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(target.name)
                        if target.deletesPermanently {
                            Text("Deletes permanently")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.destructive)
                        }
                    }
                    Text(target.paths.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(scan.map { "\($0.items.count) items · \(formatBytes($0.bytes, style: .file))" } ?? "—")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let scan, !scan.items.isEmpty {
                    Button {
                        if isExpanded { expanded.remove(target.id) } else { expanded.insert(target.id) }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.tullyIcon)
                    .accessibilityLabel(isExpanded ? "Hide items in \(target.name)" : "Show items in \(target.name)")
                }
                if !target.isBuiltIn {
                    Button { diskClean.removeCustomTarget(id: target.id) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.tullyIcon)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove target \(target.name)")
                        .help("Remove this target")
                }
            }
            if isExpanded, let scan {
                itemList(scan.items, enabled: diskClean.isSelected(target))
            }
        }
    }

    private static let maxListedItems = 200

    private func itemList(_ items: [CleanItem], enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items.prefix(Self.maxListedItems)) { item in
                HStack(spacing: 8) {
                    Toggle(isOn: Binding(get: { diskClean.isIncluded(item) },
                                         set: { diskClean.setIncluded($0, item: item) })) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                    Spacer()
                    Text(formatBytes(item.bytes, style: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.tullyIcon)
                    .accessibilityLabel("Show \(item.name) in Finder")
                    .help("Show in Finder")
                }
                .font(.callout)
            }
            if items.count > Self.maxListedItems {
                Text("and \(items.count - Self.maxListedItems) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 34)
        .disabled(!enabled)
    }

    private func clean() {
        diskClean.cleanSelected { result in
            if result.failures.isEmpty {
                toasts.show("Moved \(formatBytes(result.freedBytes, style: .file)) to the Trash")
            } else {
                toasts.show("Cleaned \(result.itemCount) items; \(result.failures.count) couldn't be removed", style: .error)
            }
        }
    }
}

// MARK: - Confirmation

private struct CleanConfirmationSheet: View {
    @Environment(DiskCleanService.self) private var diskClean
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        let byTarget = Dictionary(grouping: diskClean.selectedItems, by: \.target)
        VStack(alignment: .leading, spacing: 14) {
            Label("Move \(formatBytes(diskClean.selectedBytes, style: .file)) to the Trash?", systemImage: "trash")
                .font(.title3.weight(.semibold))
            ForEach(diskClean.allTargets.filter { byTarget[$0] != nil }) { target in
                let items = byTarget[target] ?? []
                HStack {
                    Image(systemName: target.category.icon).frame(width: 20).foregroundStyle(.secondary)
                    Text(target.name)
                    Spacer()
                    Text("\(items.count) items · \(formatBytes(items.reduce(0) { $0 + $1.item.bytes }, style: .file))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if diskClean.selectionEmptiesTrash {
                Label("Items already in the Trash are deleted permanently.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.destructive)
            }
            Text("Everything else can be restored from the Trash.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(diskClean.selectionEmptiesTrash ? "Move and Empty Trash" : "Move to Trash", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

// MARK: - Add target

struct AddCleanTargetSheet: View {
    @Environment(DiskCleanService.self) private var diskClean
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var pathsText = ""
    @State private var category: CleanTarget.Category = .caches

    private var paths: [String] {
        pathsText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var problems: [(String, String)] {
        paths.compactMap { path in
            if case .rejected(let reason) = DiskCleanPathPolicy.check(path) { return (path, reason) }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Cleanup Target").font(.title3.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(CleanTarget.Category.allCases.filter { $0 != .trash }, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                LabeledContent("Paths") {
                    TextEditor(text: $pathsText)
                        .font(.callout.monospaced())
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Paths, one per line")
                }
            }
            Text("One path per line. Use ~ for your home folder and * to match names, e.g. ~/Library/Caches/MyApp or ~/Downloads/*.tmp. ** is not supported. System folders are blocked; paths in /Users, /Library, /Applications and /Volumes must be at least 4 levels deep.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(problems, id: \.0) { path, reason in
                Label("\(path): \(reason)", systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    diskClean.addCustomTarget(CleanTarget(
                        name: name.trimmingCharacters(in: .whitespaces), paths: paths, category: category))
                    diskClean.scan()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || paths.isEmpty || !problems.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
