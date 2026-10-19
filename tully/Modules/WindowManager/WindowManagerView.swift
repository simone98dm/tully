import SwiftUI

struct WindowManagerView: View {
    @Environment(WindowManagerService.self) private var service
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        if service.isPermissionGranted {
            shortcutList
        } else {
            PermissionView()
        }
    }

    private var shortcutList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabHeader(title: "Window Zones", symbol: "rectangle.3.group",
                          subtitle: "Record a shortcut to snap the focused window.")
                ForEach(WindowZone.allCases, id: \.rawValue) { zone in
                    HStack(spacing: 10) {
                        Image(systemName: zone.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(zone.displayName)
                        Spacer()
                        ShortcutRecorder(
                            binding: service.shortcuts[zone.rawValue],
                            actionName: zone.displayName,
                            conflict: { binding in service.conflictingZone(for: binding, excluding: zone)?.displayName },
                            hasConflict: conflictFor(zone) != nil
                        ) { binding in
                            service.setShortcut(binding, for: zone)
                            toasts.show(binding.map { "\(zone.displayName): \($0.displayString)" } ?? "\(zone.displayName) shortcut cleared")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .contain)
                    Divider().padding(.leading, 46)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func conflictFor(_ zone: WindowZone) -> WindowZone? {
        guard let binding = service.shortcuts[zone.rawValue] else { return nil }
        return service.conflictingZone(for: binding, excluding: zone)
    }
}
