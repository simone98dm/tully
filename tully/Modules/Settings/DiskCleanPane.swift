import SwiftUI

struct DiskCleanPane: View {
    @Environment(DiskCleanService.self) private var diskClean
    @Environment(PopoverState.self) private var popover

    var body: some View {
        Form {
            Section {
                LabeledContent("Cleanup targets", value: "\(diskClean.allTargets.count) (\(diskClean.customTargets.count) custom)")
                Button { popover.open(.diskClean) } label: { Label("Open Disk Clean…", systemImage: "trash") }
                    .pointerStyle(.link)
            } footer: {
                Text("Disk Clean moves caches, logs, old installers and build data to the Trash. Choose targets, add your own and review every item in the Disk Clean window.")
            }
            Section("Safety") {
                Label("Items go to the Trash, so they can be restored", systemImage: "arrow.uturn.backward.circle")
                Label("System folders are always blocked", systemImage: "lock.shield")
                Label("Every path is re-checked right before it's moved", systemImage: "checkmark.shield")
            }
            Section("Permissions") {
                PermissionStatusRow(title: "Full Disk Access", detail: "Optional: lets Disk Clean read the Trash and other protected folders",
                                    isGranted: diskClean.unscannable.isEmpty, pane: .fullDiskAccess)
            }
        }
        .formStyle(.grouped)
    }
}
