import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, menuBar, windowManager, windowRing, switcher, fileConverter, diskClean, power, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:       "General"
        case .menuBar:       "Menu Bar"
        case .windowManager: "Window Manager"
        case .windowRing:    "Window Ring"
        case .switcher:      "Window Switcher"
        case .fileConverter: "File Converter"
        case .diskClean:     "Disk Clean"
        case .power:         "Power & Keyboard"
        case .about:         "About & Help"
        }
    }

    var symbol: String {
        switch self {
        case .general:       "gearshape"
        case .menuBar:       "menubar.rectangle"
        case .windowManager: "rectangle.3.group"
        case .windowRing:    "circle.dashed.inset.filled"
        case .switcher:      "rectangle.on.rectangle.angled"
        case .fileConverter: "arrow.triangle.2.circlepath"
        case .diskClean:     "trash"
        case .power:         "bolt"
        case .about:         "questionmark.circle"
        }
    }

    /// Extra words the sidebar search matches.
    var keywords: [String] {
        switch self {
        case .general:       ["login", "startup", "permissions", "accessibility", "reset", "interval", "sampling", "frequency"]
        case .menuBar:       ["status", "cpu", "memory", "ram", "network", "disk", "stats", "style"]
        case .windowManager: ["shortcuts", "zones", "snap", "tiling", "keyboard", "suggestions"]
        case .windowRing:    ["ring", "radial", "trigger", "control option", "preview", "mouse", "loop"]
        case .switcher:      ["alt tab", "hotkey", "thumbnails", "screen recording"]
        case .fileConverter: ["convert", "wheel", "drag", "ffmpeg", "pdf", "image", "video", "tools", "kumquat", "tangerine"]
        case .diskClean:     ["clean", "cache", "trash", "storage", "full disk access", "space"]
        case .power:         ["sleep", "awake", "caffeinate", "keyboard", "cleaning", "display"]
        case .about:         ["version", "help", "shortcuts", "github"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
    }
}

@Observable
final class SettingsState {
    var section: SettingsSection = .general
    var search = ""

    var visibleSections: [SettingsSection] { SettingsSection.allCases.filter { $0.matches(search) } }
}

struct SettingsView: View {
    static let minSize = CGSize(width: 760, height: 540)

    @Environment(SettingsState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(state.visibleSections, selection: Binding(
                get: { state.section },
                set: { if let section = $0 { state.section = section } }
            )) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .searchable(text: $state.search, placement: .sidebar, prompt: "Search settings")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            pane
                .navigationTitle(state.section.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: Self.minSize.width, minHeight: Self.minSize.height)
        .toastOverlay()
    }

    @ViewBuilder
    private var pane: some View {
        switch state.section {
        case .general:       GeneralPane()
        case .menuBar:       MenuBarPane()
        case .windowManager: WindowManagerPane()
        case .windowRing:    WindowRingPane()
        case .switcher:      SwitcherPane()
        case .fileConverter: FileConverterPane()
        case .diskClean:     DiskCleanPane()
        case .power:         PowerPane()
        case .about:         AboutPane()
        }
    }
}
