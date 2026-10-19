import SwiftUI

struct WindowManagerPane: View {
    @Environment(WindowManagerService.self) private var service
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        @Bindable var service = service
        Form {
            if !service.isPermissionGranted {
                Section {
                    PermissionStatusRow(title: "Accessibility", detail: "Needed to move and resize windows",
                                        isGranted: false, pane: .accessibility)
                }
            }
            Section {
                ForEach(WindowZone.allCases, id: \.rawValue) { zone in
                    LabeledContent {
                        ShortcutRecorder(
                            binding: service.shortcuts[zone.rawValue],
                            actionName: zone.displayName,
                            conflict: { service.conflictingZone(for: $0, excluding: zone)?.displayName }
                        ) { binding in
                            service.setShortcut(binding, for: zone)
                            toasts.show(binding.map { "\(zone.displayName): \($0.displayString)" } ?? "\(zone.displayName) shortcut cleared")
                        }
                    } label: {
                        Label(zone.displayName, systemImage: zone.symbol)
                    }
                }
            } header: {
                Text("Zone shortcuts")
            } footer: {
                Text("Shortcuts need ⌘, ⌃ or ⌥ so they never block typing.")
            }

            Section {
                Toggle(isOn: $service.isAutoLayoutEnabled) {
                    Text("Suggest windows for the free space")
                    Text("After a window snaps to a side, pick another open window to fill the rest of the screen.")
                }
                .accessibilityLabel("Suggest windows for the free space")
                Picker("Hide suggestions after", selection: $service.autoLayoutDelay) {
                    ForEach(WindowManagerService.autoLayoutDelays, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                .accessibilityLabel("Hide suggestions after")
                .disabled(!service.isAutoLayoutEnabled)
            } header: {
                Text("Tiling suggestions")
            }
        }
        .formStyle(.grouped)
    }
}
