import SwiftUI

struct WindowRingPane: View {
    @Environment(WindowRingService.self) private var ring
    @Environment(WindowManagerService.self) private var windowManager

    var body: some View {
        @Bindable var ring = ring
        Form {
            if !windowManager.isPermissionGranted {
                Section {
                    PermissionStatusRow(title: "Accessibility", detail: "Needed to move windows", isGranted: false, pane: .accessibility)
                }
            }
            Section {
                LabeledContent("Trigger") {
                    ModifierRecorder(flags: ring.trigger, actionName: "Window Ring") { ring.trigger = $0 }
                }
                Toggle(isOn: $ring.isRingEnabled) {
                    Text("Show the ring")
                    Text("Hold \(ring.triggerDisplay) and move the mouse toward a zone, then release to snap. Release in the middle to cancel.")
                }
                .accessibilityLabel("Show the ring")
            } header: {
                Text("Activation")
            } footer: {
                Text("The ring has no keyboard shortcuts of its own: to move windows with keys, record zone shortcuts in Window Manager. Default trigger: ⌃⌥. Click the trigger, hold the new modifiers, then release.")
            }

            Section("Ring") {
                Picker("Size", selection: $ring.ringSize) {
                    ForEach(WindowRingService.RingSize.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityLabel("Size")
                Toggle("Preview where the window will go", isOn: $ring.showsPreview)
                .accessibilityLabel("Preview where the window will go")
                Toggle("Haptic feedback on trackpads", isOn: $ring.usesHaptics)
                .accessibilityLabel("Haptic feedback on trackpads")
            }

            Section("Directions") {
                mapping("← / →", "Left / right half")
                mapping("↑ / ↓", "Top / bottom half")
                mapping("↖ ↗ ↙ ↘", "Corners")
                mapping("Far ← / →", "Left / right third")
                mapping("Far ↑", "Fullscreen")
                mapping("Far ↓", "Center third")
            }
        }
        .formStyle(.grouped)
    }

    private func mapping(_ keys: String, _ result: String) -> some View {
        LabeledContent(result) { Text(keys).font(.callout.monospaced()).foregroundStyle(.secondary) }
    }
}
