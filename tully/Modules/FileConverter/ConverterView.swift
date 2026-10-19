import AppKit
import KumquatCore
import SwiftUI
import UniformTypeIdentifiers

/// Popover tab: status, a drop zone (accessible alternative to the mid-drag wheel) and recents.
struct ConverterView: View {
    @Environment(FileConverterController.self) private var converter
    @Environment(PopoverState.self) private var popover
    @State private var isTargeted = false
    @State private var droppedFiles: [URL] = []

    private var settings: ConverterSettings { converter.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "File Converter", symbol: "arrow.triangle.2.circlepath",
                          subtitle: "Drag a file, tap ⇧ ⌘ or ⌃, drop on the wheel.") {
                    Toggle("Enable File Converter", isOn: Binding(get: { settings.isEnabled }, set: { converter.setEnabled($0) }))
                    .accessibilityLabel("Enable File Converter")
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .pointerStyle(.link)
                }
                .padding(.horizontal, -16)

                if settings.isEnabled {
                    dropZone
                    dependencies
                    recents
                } else {
                    EmptyStateView(symbol: "power", message: "The File Converter is off. Turn it on to use the drag wheels.",
                                   actionTitle: "Turn On") { converter.setEnabled(true) }
                }
            }
            .padding(16)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 26))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            Text(droppedFiles.isEmpty ? "Drop files here" : droppedFiles.count == 1 ? droppedFiles[0].lastPathComponent : "\(droppedFiles.count) files")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                actionButton("Convert", symbol: "arrow.triangle.2.circlepath", kind: .convert)
                actionButton("Tools", symbol: "wrench.and.screwdriver", kind: .tools)
                actionButton("Actions", symbol: "square.and.arrow.up", kind: .actions)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isTargeted ? Color.accentColor : .secondary.opacity(0.4),
                                                                 style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadURLs(providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone. Drop files, then pick Convert, Tools or Actions. Or use Choose Files.")
    }

    private func actionButton(_ title: String, symbol: String, kind: WheelKind) -> some View {
        Button {
            if droppedFiles.isEmpty {
                switch kind {
                case .convert: converter.chooseConvert()
                case .tools: converter.chooseTools()
                case .actions: converter.chooseActions()
                }
            } else {
                converter.offer(kind, for: droppedFiles, at: NSEvent.mouseLocation)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bordered)
        .pointerStyle(.link)
        .help(droppedFiles.isEmpty ? "Choose files to \(title.lowercased())" : "\(title) the dropped files")
    }

    private var dependencies: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Helpers").font(.subheadline).foregroundStyle(.secondary)
            DependencyRow(name: "ffmpeg", purpose: "video and audio", install: "brew install ffmpeg")
            DependencyRow(name: "cwebp", purpose: "WebP output", install: "brew install webp")
        }
    }

    @ViewBuilder
    private var recents: some View {
        let existing = settings.recents.filter { FileManager.default.fileExists(atPath: $0) }
        if !existing.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Recent results").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { settings.clearRecents() }.buttonStyle(.tully).font(.caption)
                }
                ForEach(existing.prefix(5), id: \.self) { path in
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: {
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.icon(forFile: path)).resizable().frame(width: 16, height: 16)
                            Text((path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.tullyRow)
                    .accessibilityHint("Shows the file in Finder")
                }
            }
            .padding(.horizontal, -8)
        }
    }

    private func loadURLs(_ providers: [NSItemProvider]) {
        droppedFiles = []
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { droppedFiles.append(url) }
            }
        }
    }
}

/// Whether a command-line helper is installed, with a copyable install command.
struct DependencyRow: View {
    let name: String
    let purpose: String
    let install: String
    @State private var path: String?
    @State private var checked = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: path != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(path != nil ? Color.green : Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(name) · \(purpose)").font(.caption.weight(.medium))
                Text(path ?? (checked ? "Not found: \(install)" : "Checking…"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if checked, path == nil {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(install, forType: .string)
                }
                .buttonStyle(.tully)
                .font(.caption)
                .accessibilityLabel("Copy install command for \(name)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(path != nil ? "Installed" : "Not installed")
        .task {
            let name = name
            path = await Task.detached { Shell.which(name) }.value
            checked = true
        }
    }
}
