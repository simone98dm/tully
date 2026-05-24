// tully/Modules/WindowManager/WindowManagerView.swift
import SwiftUI
import AppKit

struct WindowManagerView: View {
    @State private var service = WindowManagerService()
    @State private var recordingZone: WindowZone? = nil
    @State private var localMonitor: Any? = nil

    var body: some View {
        Group {
            if service.isPermissionGranted {
                shortcutList
            } else {
                PermissionView()
            }
        }
        .onAppear { service.setup() }
        .onDisappear {
            service.teardown()
            stopRecording()
        }
    }

    // MARK: - Shortcut List

    private var shortcutList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Window Zones")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ForEach(WindowZone.allCases, id: \.rawValue) { zone in
                    ShortcutRow(
                        zone: zone,
                        binding: service.shortcuts[zone.rawValue],
                        isRecording: recordingZone == zone,
                        hasConflict: conflictFor(zone) != nil
                    ) {
                        toggleRecording(for: zone)
                    } onClear: {
                        service.setShortcut(nil, for: zone)
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Recording

    private func toggleRecording(for zone: WindowZone) {
        if recordingZone == zone {
            stopRecording()
        } else {
            stopRecording()
            recordingZone = zone
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let binding = ShortcutBinding(
                    keyCode: event.keyCode,
                    modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).rawValue
                        & ~CGEventFlags.maskNonCoalesced.rawValue
                )
                self.service.setShortcut(binding, for: zone)
                self.stopRecording()
                return nil // consume
            }
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        recordingZone = nil
    }

    private func conflictFor(_ zone: WindowZone) -> WindowZone? {
        guard let binding = service.shortcuts[zone.rawValue] else { return nil }
        return service.conflictingZone(for: binding, excluding: zone)
    }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
    let zone: WindowZone
    let binding: ShortcutBinding?
    let isRecording: Bool
    let hasConflict: Bool
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(zone.displayName)
                .font(.body)
            Spacer()
            if isRecording {
                Text("Recording…")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if let b = binding {
                HStack(spacing: 4) {
                    Text(b.displayString)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(hasConflict ? Color.red.opacity(0.15) : Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(hasConflict ? .red : .primary)
                        .help(hasConflict ? "Conflict with another zone" : "")
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
