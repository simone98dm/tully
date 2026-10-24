import CoreGraphics
import Foundation

/// Switcher key handling. Runs on the EventTapService thread; thread safety via NSLock.
nonisolated final class TabHotkeyHandler: @unchecked Sendable {
    var isOverlayVisible: Bool {
        get { lock.withLock { _overlayVisible } }
        set { lock.withLock { _overlayVisible = newValue } }
    }
    var hotkey: ShortcutBinding? {
        get { lock.withLock { _hotkey } }
        set { lock.withLock { _hotkey = newValue } }
    }

    // set once before the handler is registered with the tap
    var onActivate: (@Sendable () -> Void)?
    var onTab: (@Sendable (Bool) -> Void)?    // Bool = isShift (reverse)
    var onConfirm: (@Sendable () -> Void)?
    var onDismiss: (@Sendable () -> Void)?
    var onQuit: (@Sendable () -> Void)?       // quit the selected window's app

    private let lock = NSLock()
    private var _overlayVisible = false
    private var _hotkey: ShortcutBinding?
    // Recorded at activation time — used to detect release
    private var _activationKeyCode: UInt16 = 0
    private var _activationModifiers: UInt64 = 0

    /// Events were missed (tap was disabled): close the overlay rather than keep swallowing keys.
    func reset() {
        let wasVisible = lock.withLock {
            defer { _overlayVisible = false }
            return _overlayVisible
        }
        if wasVisible {
            let cb = onDismiss
            DispatchQueue.main.async { cb?() }
        }
    }

    /// Returns true to consume the event.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let overlayVisible = lock.withLock { _overlayVisible }

        switch type {

        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let mods = event.flags.rawValue & ShortcutBinding.userModifiers.rawValue

            if overlayVisible {
                switch keyCode {
                case 48: // Tab — cycle
                    let shift = (mods & CGEventFlags.maskShift.rawValue) != 0
                    let cb = onTab
                    DispatchQueue.main.async { cb?(shift) }
                    return true
                case 123, 124: // ← / → — move
                    let cb = onTab
                    DispatchQueue.main.async { cb?(keyCode == 123) }
                    return true
                case 53: // Esc — dismiss
                    let cb = onDismiss
                    DispatchQueue.main.async { cb?() }
                    return true
                case 36, 76: // Return / Enter — confirm
                    let cb = onConfirm
                    DispatchQueue.main.async { cb?() }
                    return true
                default:
                    // Q as printed on the user's layout, so ⌥Q works on AZERTY too
                    if ShortcutBinding.keyName(keyCode) == "Q" {
                        let cb = onQuit
                        DispatchQueue.main.async { cb?() }
                        return true
                    }
                }
            }

            // Check activation hotkey
            if let hk = lock.withLock({ _hotkey }) {
                let binding = ShortcutBinding(keyCode: keyCode, modifiers: mods)
                // a held hotkey auto-repeats: consume repeats without reopening (it would reset the selection)
                if binding == hk, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
                if binding == hk {
                    // Record which key/mods triggered activation so we know what to watch for on release
                    lock.withLock {
                        _activationKeyCode = keyCode
                        _activationModifiers = hk.modifiers
                    }
                    let cb = onActivate
                    DispatchQueue.main.async { cb?() }
                    return true
                }
            }

        case .keyUp:
            guard overlayVisible else { break }
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let (actKey, actMods) = lock.withLock { (_activationKeyCode, _activationModifiers) }
            // For plain-key hotkeys (no modifiers): confirm when the trigger key is released.
            // For modifier+key hotkeys: confirmation happens via flagsChanged (below), not here,
            // because the user may still want to keep pressing Tab while holding the modifier.
            if keyCode == actKey && actMods == 0 {
                let cb = onConfirm
                DispatchQueue.main.async { cb?() }
                return true
            }

        case .flagsChanged:
            guard overlayVisible else { break }
            let currentMods = event.flags.rawValue & ShortcutBinding.userModifiers.rawValue
            let actMods = lock.withLock { _activationModifiers }
            // Confirm when ALL modifier keys that were part of the hotkey are released
            if actMods != 0 && (currentMods & actMods) == 0 {
                let cb = onConfirm
                DispatchQueue.main.async { cb?() }
                // Pass through so the target app sees the modifier release with clean state
                return false
            }

        default:
            break
        }

        return false
    }
}
