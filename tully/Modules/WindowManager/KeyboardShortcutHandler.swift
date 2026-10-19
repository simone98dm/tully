import CoreGraphics
import Foundation

/// Matches key-downs against zone shortcuts. Runs on the EventTapService thread.
nonisolated final class KeyboardShortcutHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var _bindings: [ShortcutBinding: WindowZone] = [:]
    private var _onZoneTriggered: (@Sendable (WindowZone) -> Void)?

    var onZoneTriggered: (@Sendable (WindowZone) -> Void)? {
        get { lock.withLock { _onZoneTriggered } }
        set { lock.withLock { _onZoneTriggered = newValue } }
    }

    var bindings: [ShortcutBinding: WindowZone] {
        get { lock.withLock { _bindings } }
        set { lock.withLock { _bindings = newValue } }
    }

    /// Returns true (consume) when the event is a bound shortcut.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown else { return false }
        let binding = ShortcutBinding(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: event.flags.rawValue
        )
        guard let zone = bindings[binding] else { return false }
        let callback = onZoneTriggered
        DispatchQueue.main.async { callback?(zone) }
        return true
    }
}
