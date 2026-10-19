import AppKit
import SwiftUI

/// Records a modifier-only combination (e.g. ⌃⌥): hold the keys, then release.
struct ModifierRecorder: View {
    let flags: CGEventFlags
    let actionName: String
    let onChange: (CGEventFlags) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var peak: CGEventFlags = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: toggle) {
                Text(isRecording ? (peak.isEmpty ? "Hold modifiers…" : ShortcutBinding.modifierSymbols(peak))
                                 : ShortcutBinding.modifierSymbols(flags))
                    .font(.callout.monospaced().weight(.medium))
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
                    .frame(minWidth: 90)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.tully)
            .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isRecording ? Color.accentColor : .secondary.opacity(0.3)))
            .accessibilityLabel("Trigger for \(actionName)")
            .accessibilityValue(ShortcutBinding.modifierSymbols(flags))
            .accessibilityHint("Hold two or more modifier keys, then release them")
            if let message {
                Text(message).font(.caption).foregroundStyle(Theme.warning)
            }
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        guard !isRecording else { stop(); return }
        isRecording = true
        peak = []
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                if event.keyCode == ShortcutBinding.escapeKeyCode { stop() }
                return nil
            }
            let current = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(ShortcutBinding.userModifiers)
            if current.isEmpty {
                finish()
            } else if current.rawValue.nonzeroBitCount >= peak.rawValue.nonzeroBitCount {
                peak = current
            }
            return event
        }
    }

    private func finish() {
        let recorded = peak
        stop()
        guard recorded.rawValue.nonzeroBitCount >= 2 else {
            message = "Use at least two modifiers so normal shortcuts keep working"
            return
        }
        onChange(recorded)
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
