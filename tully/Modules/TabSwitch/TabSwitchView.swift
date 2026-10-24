import SwiftUI

struct TabSwitchView: View {
    @Environment(TabSwitchService.self) private var service
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TabHeader(title: "Window Switcher", symbol: "rectangle.on.rectangle.angled",
                          subtitle: "Switch between any windows, even of the same app.") {
                    Toggle("Enable window switcher", isOn: Binding(
                        get: { service.isEnabled },
                        set: { service.setEnabled($0); toasts.show($0 ? "Switcher on" : "Switcher off", style: .info) }
                    ))
                    .accessibilityLabel("Enable window switcher")
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!service.isPermissionGranted)
                    .pointerStyle(.link)
                }
                .padding(.horizontal, -16)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activation shortcut")
                        Spacer()
                        ShortcutRecorder(binding: service.hotkey, actionName: "Window Switcher") { binding in
                            service.setHotkey(binding)
                            toasts.show(binding.map { "Switcher: \($0.displayString)" } ?? "Switcher shortcut cleared")
                        }
                    }
                    Text("Hold the modifier and press Tab / ⇧Tab or ← → to move, Q to quit the selected app. Release it (or press Return) to switch, Esc to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !service.isPermissionGranted || !service.hasScreenRecordingPermission {
                    Divider()
                    permissionsSection
                }
            }
            .padding(16)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.subheadline).foregroundStyle(.secondary)
            if !service.isPermissionGranted {
                PermissionRow(icon: "lock.shield", title: "Accessibility",
                              description: "Required to bring windows to the front", pane: .accessibility)
            }
            if !service.hasScreenRecordingPermission {
                PermissionRow(icon: "video.slash", title: "Screen Recording",
                              description: "Optional: shows live window thumbnails", pane: .screenRecording)
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let pane: PermissionCenter.Pane

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.warning)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Enable") { PermissionCenter.openSettings(pane) }
                .buttonStyle(.bordered)
                .pointerStyle(.link)
                .accessibilityLabel("Enable \(title) in System Settings")
        }
        .padding(10)
        .background(Theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }
}
