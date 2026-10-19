import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case system, disk, windows, tabSwitch, converter

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system:    "System"
        case .disk:      "Disk"
        case .windows:   "Windows"
        case .tabSwitch: "Switcher"
        case .converter: "Convert"
        }
    }

    var icon: String {
        switch self {
        case .system:    "cpu"
        case .disk:      "internaldrive"
        case .windows:   "rectangle.3.group"
        case .tabSwitch: "rectangle.on.rectangle.angled"
        case .converter: "arrow.triangle.2.circlepath"
        }
    }

    /// ⌘1…⌘n
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String(rawValue + 1))) }
}

/// Popover navigation, shared so any view (e.g. the Disk ring) can switch tabs.
@Observable
final class PopoverState {
    var selectedTab: AppTab = .system
    /// Tabs opened at least once; kept alive afterwards so state and scroll position survive.
    private(set) var visitedTabs: Set<AppTab> = [.system]
    enum Destination: Equatable {
        case settings(SettingsSection?)
        case systemMonitor
        case diskClean
        case about
    }

    /// Opens a window outside the popover (wired by AppDelegate).
    @ObservationIgnored var open: (Destination) -> Void = { _ in }

    func select(_ tab: AppTab) {
        visitedTabs.insert(tab)
        selectedTab = tab
    }

    func selectAdjacent(_ offset: Int) {
        let all = AppTab.allCases
        let index = (selectedTab.rawValue + offset + all.count) % all.count
        select(all[index])
    }
}

struct ContentView: View {
    // tall enough for the whole System tab without scrolling (content 443 pt + tab bar + quick toggles)
    static let size = CGSize(width: 360, height: 582)

    @Environment(PopoverState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    if state.visitedTabs.contains(tab) {
                        page(for: tab)
                            .opacity(state.selectedTab == tab ? 1 : 0)
                            .allowsHitTesting(state.selectedTab == tab)
                            .accessibilityHidden(state.selectedTab != tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: state.selectedTab)
            Divider()
            QuickToggleBar()
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .toastOverlay()
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = state.selectedTab == tab
                Button { state.select(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 14))
                        Text(tab.title).font(.caption2.weight(isSelected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                                .fill(Color.accentColor.opacity(0.14))
                                .matchedGeometryEffect(id: "selection", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(TullyButtonStyle(kind: .tab))
                .keyboardShortcut(tab.shortcut, modifiers: .command)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Command \(tab.rawValue + 1)")
                .help("\(tab.title) (⌘\(tab.rawValue + 1))")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .safeAreaInset(edge: .trailing, spacing: 0) { settingsButton }
        .background(.bar)
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: state.selectedTab)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { state.selectAdjacent(-1); return .handled }
        .onKeyPress(.rightArrow) { state.selectAdjacent(1); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private var settingsButton: some View {
        Button { state.open(.settings(nil)) } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 36)
        }
        .buttonStyle(.tullyIcon)
        .keyboardShortcut(",", modifiers: .command)
        .accessibilityLabel("Settings")
        .help("Settings (⌘,)")
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private func page(for tab: AppTab) -> some View {
        switch tab {
        case .system:    SystemMonitorView()
        case .disk:      DiskUtilityView()
        case .windows:   WindowManagerView()
        case .tabSwitch: TabSwitchView()
        case .converter: ConverterView()
        }
    }
}
