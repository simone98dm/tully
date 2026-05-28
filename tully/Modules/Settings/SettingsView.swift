// tully/Modules/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WindowManagerService.self) private var windowManager
    @Environment(TabSwitchService.self) private var tabSwitch
    @State private var showResetConfirmation = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Menu Bar")

                VStack(spacing: 0) {
                    SettingsToggleRow(label: "Show CPU usage", isOn: $settings.showCPU)
                    Divider().padding(.leading, 12)
                    SettingsToggleRow(label: "Show RAM usage", isOn: $settings.showRAM)
                    Divider().padding(.leading, 12)
                    SettingsToggleRow(label: "Show Network", isOn: $settings.showNet)
                }
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer().frame(height: 24)

                sectionHeader("Danger Zone")

                Button {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Reset all configuration")
                                .foregroundStyle(.red)
                            Text("Clears shortcuts and display settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .confirmationDialog(
            "Reset all configuration?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                settings.resetAll()
                windowManager.reset()
                tabSwitch.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears all keyboard shortcuts and display settings. Cannot be undone.")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 6)
            .padding(.leading, 4)
    }
}

private struct SettingsToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
