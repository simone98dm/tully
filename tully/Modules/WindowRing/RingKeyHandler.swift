import CoreGraphics
import Foundation

/// Watches the ring trigger (default ⌃⌥) on the EventTapService thread. It has no key shortcuts of
/// its own: modifier events always pass through, and only Esc is consumed while the ring shows.
nonisolated final class RingKeyHandler: @unchecked Sendable {
    enum Signal: Equatable, Sendable {
        case triggerDown
        case triggerUp(apply: Bool)
        case cancel
    }

    private let lock = NSLock()
    private var _trigger: UInt64
    private var _ringVisible = false
    private var isHeld = false
    /// Another key was pressed with the trigger (some other shortcut): don't show the ring this time.
    private var usedForOtherKey = false
    /// Mouse buttons held (e.g. a file drag for the converter) never start the ring.
    var isMouseButtonDown: () -> Bool = {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    var onSignal: (@Sendable (Signal) -> Void)?

    init(trigger: CGEventFlags) {
        _trigger = trigger.rawValue & ShortcutBinding.userModifiers.rawValue
    }

    var trigger: CGEventFlags {
        get { CGEventFlags(rawValue: lock.withLock { _trigger }) }
        set { lock.withLock { _trigger = newValue.rawValue & ShortcutBinding.userModifiers.rawValue } }
    }

    var isRingVisible: Bool {
        get { lock.withLock { _ringVisible } }
        set { lock.withLock { _ringVisible = newValue } }
    }

    /// True while the trigger is held and no other key interfered: the ring may open.
    var mayShowRing: Bool { lock.withLock { isHeld && !usedForOtherKey } }

    /// Events were missed (tap was disabled): forget the held trigger and cancel a ring in progress.
    func reset() {
        let wasHeld = lock.withLock {
            defer { isHeld = false; _ringVisible = false }
            return isHeld
        }
        if wasHeld { send(.triggerUp(apply: false)) }
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let mods = event.flags.rawValue & ShortcutBinding.userModifiers.rawValue
        switch type {
        case .flagsChanged:
            handleFlags(mods)
            return false
        case .keyDown:
            return handleKeyDown(UInt16(event.getIntegerValueField(.keyboardEventKeycode)), mods: mods)
        default:
            return false
        }
    }

    private func handleFlags(_ mods: UInt64) {
        var signal: Signal?
        lock.withLock {
            let exact = mods == _trigger && _trigger != 0
            if exact, !isHeld {
                guard !isMouseButtonDown() else { return }
                isHeld = true
                usedForOtherKey = false
                signal = .triggerDown
            } else if !exact, isHeld {
                isHeld = false
                // releasing applies; adding another modifier means a different shortcut, so cancel
                let released = mods & _trigger == mods
                signal = .triggerUp(apply: released && !usedForOtherKey)
            }
        }
        if let signal { send(signal) }
    }

    /// Esc cancels an open ring; any other key means the trigger was part of another shortcut,
    /// which is passed through untouched.
    private func handleKeyDown(_ code: UInt16, mods: UInt64) -> Bool {
        var signal: Signal?
        let consumed: Bool = lock.withLock {
            guard isHeld, mods == _trigger else { return false }
            if code == ShortcutBinding.escapeKeyCode, _ringVisible {
                signal = .cancel
                return true
            }
            usedForOtherKey = true
            return false
        }
        if let signal { send(signal) }
        return consumed
    }

    private func send(_ signal: Signal) {
        let callback = onSignal
        DispatchQueue.main.async { callback?(signal) }
    }
}
