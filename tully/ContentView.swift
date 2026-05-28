// tully/ContentView.swift
import SwiftUI

private enum AppTab: Int, CaseIterable {
    case system, disk, windows, tabSwitch, settings

    var title: String {
        switch self {
        case .system:    "System"
        case .disk:      "Disk"
        case .windows:   "Windows"
        case .tabSwitch: "Switcher"
        case .settings:  "Settings"
        }
    }

    var icon: String {
        switch self {
        case .system:    "cpu"
        case .disk:      "internaldrive"
        case .windows:   "rectangle.3.group"
        case .tabSwitch: "rectangle.on.rectangle.angled"
        case .settings:  "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .system

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.title)
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.bar)

            Divider()

            Group {
                switch selectedTab {
                case .system:    SystemMonitorView()
                case .disk:      DiskUtilityView()
                case .windows:   WindowManagerView()
                case .tabSwitch: TabSwitchView()
                case .settings:  SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 340, height: 480)
    }
}
