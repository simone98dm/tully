import SwiftUI

/// Explains a missing permission and links to System Settings. Disappears by itself once granted
/// (PermissionCenter re-checks), so no relaunch is needed.
struct PermissionView: View {
    var title = "Accessibility Required"
    var message = "tully needs Accessibility access to move and resize windows."
    var pane: PermissionCenter.Pane = .accessibility

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                PermissionCenter.openSettings(pane)
            } label: {
                Label("Open System Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .pointerStyle(.link)
            Text("This screen updates as soon as access is granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
