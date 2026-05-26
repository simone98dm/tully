// tully/Modules/TabSwitch/TabHotkeyHandler.swift
import CoreGraphics
import Foundation

// File-scope C callback — avoids @MainActor inference with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
private func tabEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let handler = Unmanaged<TabHotkeyHandler>.fromOpaque(userInfo).takeUnretainedValue()
    return handler.handle(type: type, event: event)
}

// @unchecked Sendable: thread safety managed via NSLock
final class TabHotkeyHandler: @unchecked Sendable {
    var isOverlayVisible: Bool {
        get { lock.withLock { _overlayVisible } }
        set { lock.withLock { _overlayVisible = newValue } }
    }
    var hotkey: ShortcutBinding? {
        get { lock.withLock { _hotkey } }
        set { lock.withLock { _hotkey = newValue } }
    }

    var onActivate: (() -> Void)?
    var onTab: ((Bool) -> Void)?    // Bool = isShift (reverse)
    var onConfirm: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let lock = NSLock()
    private var _overlayVisible = false
    private var _hotkey: ShortcutBinding?
    // Recorded at activation time — used to detect release
    private var _activationKeyCode: UInt16 = 0
    private var _activationModifiers: UInt64 = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var selfUnmanaged: Unmanaged<TabHotkeyHandler>?

    func start() {
        guard eventTap == nil else { return }
        // Intercept keyDown, keyUp, and flagsChanged so we can confirm on key release
        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let unmanaged = Unmanaged.passRetained(self)
        selfUnmanaged = unmanaged

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tabEventTapCallback,
            userInfo: unmanaged.toOpaque()
        ) else {
            selfUnmanaged?.release()
            selfUnmanaged = nil
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let ready = DispatchSemaphore(value: 0)
        tapThread = Thread {
            self.tapRunLoop = CFRunLoopGetCurrent()
            ready.signal()
            if let src = self.runLoopSource {
                CFRunLoopAddSource(self.tapRunLoop, src, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        tapThread?.name = "com.tully.tabswitchtap"
        tapThread?.start()
        ready.wait()
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        selfUnmanaged?.release()
        selfUnmanaged = nil
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        tapRunLoop = nil
    }

    // Called on CGEventTap thread — must NOT touch MainActor state directly
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let overlayVisible = lock.withLock { _overlayVisible }

        switch type {

        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let mods = event.flags.rawValue & ~CGEventFlags.maskNonCoalesced.rawValue

            if overlayVisible {
                switch keyCode {
                case 48: // Tab — cycle
                    let shift = (mods & CGEventFlags.maskShift.rawValue) != 0
                    let cb = onTab
                    DispatchQueue.main.async { cb?(shift) }
                    return nil
                case 53: // Esc — dismiss
                    let cb = onDismiss
                    DispatchQueue.main.async { cb?() }
                    return nil
                default:
                    break
                }
            }

            // Check activation hotkey
            if let hk = lock.withLock({ _hotkey }) {
                let binding = ShortcutBinding(keyCode: keyCode, modifiers: mods)
                if binding == hk {
                    // Record which key/mods triggered activation so we know what to watch for on release
                    lock.withLock {
                        _activationKeyCode = keyCode
                        _activationModifiers = hk.modifiers
                    }
                    let cb = onActivate
                    DispatchQueue.main.async { cb?() }
                    return nil
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
                return nil
            }

        case .flagsChanged:
            guard overlayVisible else { break }
            let currentMods = event.flags.rawValue & ~CGEventFlags.maskNonCoalesced.rawValue
            let actMods = lock.withLock { _activationModifiers }
            // Confirm when ALL modifier keys that were part of the hotkey are released
            if actMods != 0 && (currentMods & actMods) == 0 {
                let cb = onConfirm
                DispatchQueue.main.async { cb?() }
                // Pass through so the target app sees the modifier release with clean state
                return Unmanaged.passRetained(event)
            }

        default:
            break
        }

        return Unmanaged.passRetained(event)
    }
}
