import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(AppSettings.self) private var settings
    @Environment(WindowManagerService.self) private var windowManager
    @Environment(TabSwitchService.self) private var tabSwitch
    @Environment(ToastCenter.self) private var toasts
    @Environment(SystemMonitorService.self) private var monitor
    @Environment(WindowRingService.self) private var ring
    @Environment(FileConverterController.self) private var converter
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Launch at login")
                    Text("Start tully automatically when you log in.")
                }
                .accessibilityLabel("Launch at login")
                if let launchError {
                    Label(launchError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                }
            }

            Section {
                Picker("Update stats every", selection: Binding(get: { monitor.interval }, set: { monitor.interval = $0 })) {
                    ForEach(SystemMonitorService.intervals, id: \.self) { Text("\(Int($0)) s").tag($0) }
                }
                .accessibilityLabel("Update stats every")
            } header: {
                Text("System monitoring")
            } footer: {
                Text("Process lists and sensors are only read while the popover or System Monitor window is open.")
            }

            Section {
                PermissionStatusRow(title: "Accessibility", detail: "Window zones, switcher and keyboard features",
                                    isGranted: permissions.isAccessibilityGranted, pane: .accessibility)
                PermissionStatusRow(title: "Screen Recording", detail: "Live thumbnails in the window switcher (optional)",
                                    isGranted: permissions.isScreenRecordingGranted, pane: .screenRecording)
            } header: {
                Text("Permissions")
            } footer: {
                Text("Changes are picked up automatically; no relaunch needed.")
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                    .pointerStyle(.link)
            } footer: {
                Text("Clears shortcuts, menu bar options and feature switches.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                settings.resetAll()
                windowManager.reset()
                tabSwitch.reset()
                ring.reset()
                converter.settings.reset()
                converter.apply(showOnboarding: false)
                toasts.show("All settings were reset")
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch {
            launchError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Granted / missing permission with a link to System Settings.
struct PermissionStatusRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let pane: PermissionCenter.Pane

    var body: some View {
        HStack {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGranted ? Color.green : Theme.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Text("Granted").foregroundStyle(.secondary)
            } else {
                Button("Open System Settings") { PermissionCenter.openSettings(pane) }
                    .pointerStyle(.link)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Granted" : "Not granted")
    }
}
