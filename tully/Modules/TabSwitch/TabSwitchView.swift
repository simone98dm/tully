// tully/Modules/TabSwitch/TabSwitchView.swift
import AppKit
import CoreGraphics
import SwiftUI

struct TabSwitchView: View {
    @Environment(TabSwitchService.self) private var service
    @State private var isRecordingHotkey = false
    @State private var localMonitor: Any? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow
                Divider()
                hotkeySection
                if !service.isPermissionGranted || !service.hasScreenRecordingPermission {
                    Divider()
                    permissionsSection
                }
            }
            .padding(16)
        }
        .onDisappear { stopRecording() }
    }

    // MARK: Header

    private var headerRow: some View {
        HStack {
            Label("Tab Switcher", systemImage: "rectangle.on.rectangle.angled")
                .font(.headline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { service.isEnabled },
                set: { service.setEnabled($0) }
            ))
            .labelsHidden()
            .disabled(!service.isPermissionGranted)
        }
    }

    // MARK: Hotkey

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activation Shortcut")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Switch windows")
                    .font(.body)
                Spacer()
                if isRecordingHotkey {
                    Text("Recording…")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if let b = service.hotkey {
                    HStack(spacing: 4) {
                        Text(b.displayString)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Button {
                            service.setHotkey(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Text("—").foregroundStyle(.tertiary).padding(.horizontal, 8)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleRecording() }

            Text("Navigate with Tab / Shift+Tab. Press Enter to focus the selected window.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions").font(.subheadline).foregroundStyle(.secondary)

            if !service.isPermissionGranted {
                PermissionRow(
                    icon: "lock.shield",
                    title: "Accessibility",
                    description: "Required to bring windows to front",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            }
            if !service.hasScreenRecordingPermission {
                PermissionRow(
                    icon: "video.slash",
                    title: "Screen Recording",
                    description: "Required for window thumbnails",
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
            }
        }
    }

    // MARK: Recording

    private func toggleRecording() {
        if isRecordingHotkey {
            stopRecording()
        } else {
            isRecordingHotkey = true
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let binding = ShortcutBinding(
                    keyCode: event.keyCode,
                    modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).rawValue
                        & ~CGEventFlags.maskNonCoalesced.rawValue
                )
                self.service.setHotkey(binding)
                self.stopRecording()
                return nil
            }
        }
    }

    private func stopRecording() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        isRecordingHotkey = false
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let url: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Enable") {
                NSWorkspace.shared.open(URL(string: url)!)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.blue)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
