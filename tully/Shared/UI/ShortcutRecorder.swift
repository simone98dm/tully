import AppKit
import SwiftUI

/// Click to record a key combo, ✕ to clear. Esc cancels. Rejects combos without ⌘/⌃/⌥ and asks
/// before taking a combo another action already uses.
struct ShortcutRecorder: View {
    let binding: ShortcutBinding?
    /// What the shortcut does, for VoiceOver ("Left Half").
    let actionName: String
    /// Name of another action already using a combo, if any.
    var conflict: (ShortcutBinding) -> String? = { _ in nil }
    /// Highlights an existing duplicate (e.g. from older settings).
    var hasConflict = false
    let onChange: (ShortcutBinding?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?
    @State private var pending: ShortcutBinding?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 2) {
                Button(action: toggleRecording) {
                    Text(label)
                        .font(.callout.monospaced().weight(.medium))
                        .foregroundStyle(isRecording ? Color.accentColor : hasConflict ? Theme.destructive : .primary)
                        .frame(minWidth: 76)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.tully)
                .accessibilityLabel("Shortcut for \(actionName)")
                .accessibilityValue(isRecording ? "Recording" : binding?.displayString ?? "None")
                .accessibilityHint(isRecording ? "Press the new key combination, or Escape to cancel" : "Records a new shortcut")
                .help(isRecording ? "Press keys… (Esc to cancel)" : "Click to record a shortcut")

                if binding != nil, !isRecording {
                    Button {
                        onChange(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.tullyIcon)
                    .accessibilityLabel("Clear shortcut for \(actionName)")
                    .help("Clear shortcut")
                }
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: isRecording ? 1.5 : 1)
            }

            if hasConflict, !isRecording, pending == nil {
                Label("Used twice", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.destructive)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .multilineTextAlignment(.trailing)
            }
            if let pending {
                HStack(spacing: 6) {
                    Button("Replace") {
                        onChange(pending)
                        clearPending()
                    }
                    .buttonStyle(.tully)
                    Button("Cancel", action: clearPending)
                        .buttonStyle(.tully)
                }
                .font(.caption)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Press keys…" }
        return binding?.displayString ?? "Record"
    }

    private var borderColor: Color {
        if isRecording { return .accentColor }
        return hasConflict ? Theme.destructive.opacity(0.7) : .secondary.opacity(0.3)
    }

    private func toggleRecording() {
        guard !isRecording else { stopRecording(); return }
        clearPending()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == ShortcutBinding.escapeKeyCode {
                stopRecording()
                return nil
            }
            let recorded = ShortcutBinding(
                keyCode: event.keyCode,
                modifiers: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).rawValue
            )
            if let error = recorded.validationError {
                message = error
                NSSound.beep()
                return nil
            }
            stopRecording()
            if recorded != binding, let other = conflict(recorded) {
                pending = recorded
                message = "\(recorded.displayString) is used by \(other)."
            } else {
                onChange(recorded)
            }
            return nil
        }
    }

    private func clearPending() {
        pending = nil
        message = nil
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        if pending == nil { message = nil }
    }
}
