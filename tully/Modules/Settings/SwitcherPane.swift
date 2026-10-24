import SwiftUI

struct SwitcherPane: View {
    @Environment(TabSwitchService.self) private var service
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { service.isEnabled }, set: { service.setEnabled($0) })) {
                    Text("Enable window switcher")
                    Text("Shows every window, including several of the same app, with live previews.")
                }
                .accessibilityLabel("Enable window switcher")
                .disabled(!service.isPermissionGranted)
                LabeledContent("Activation shortcut") {
                    ShortcutRecorder(binding: service.hotkey, actionName: "Window Switcher") { service.setHotkey($0) }
                }
            } footer: {
                Text("Hold the modifier and press Tab / ⇧Tab or ← → to move, Q to quit the selected app. Release it (or press Return) to switch, Esc to cancel.")
            }
            Section("Permissions") {
                PermissionStatusRow(title: "Accessibility", detail: "Brings the chosen window to the front",
                                    isGranted: permissions.isAccessibilityGranted, pane: .accessibility)
                PermissionStatusRow(title: "Screen Recording", detail: "Live thumbnails (app icons otherwise)",
                                    isGranted: permissions.isScreenRecordingGranted, pane: .screenRecording)
            }
        }
        .formStyle(.grouped)
    }
}
