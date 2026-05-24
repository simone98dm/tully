// tully/Modules/WindowManager/KeyboardShortcutHandler.swift
import CoreGraphics
import Foundation

// File-scope C callback — avoids @MainActor inference issues with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let handler = Unmanaged<KeyboardShortcutHandler>.fromOpaque(userInfo).takeUnretainedValue()
    return handler.handleEvent(proxy: proxy, type: type, event: event)
}

// @unchecked Sendable: thread safety managed manually via NSLock
final class KeyboardShortcutHandler: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var selfUnmanaged: Unmanaged<KeyboardShortcutHandler>?

    private let lock = NSLock()
    private var _bindings: [ShortcutBinding: WindowZone] = [:]
    private var _onZoneTriggered: ((WindowZone) -> Void)?

    var onZoneTriggered: ((WindowZone) -> Void)? {
        get { lock.withLock { _onZoneTriggered } }
        set { lock.withLock { _onZoneTriggered = newValue } }
    }

    var bindings: [ShortcutBinding: WindowZone] {
        get { lock.withLock { _bindings } }
        set { lock.withLock { _bindings = newValue } }
    }

    func start() {
        guard eventTap == nil else { return } // prevent double-start
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let unmanaged = Unmanaged.passRetained(self)
        selfUnmanaged = unmanaged
        let selfPtr = unmanaged.toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            selfUnmanaged?.release()
            selfUnmanaged = nil
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        let readySemaphore = DispatchSemaphore(value: 0)
        tapThread = Thread {
            self.tapRunLoop = CFRunLoopGetCurrent()
            readySemaphore.signal()     // signal BEFORE adding source + running
            if let source = self.runLoopSource {
                CFRunLoopAddSource(self.tapRunLoop, source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        tapThread?.name = "com.mymenu.eventtap"
        tapThread?.start()
        readySemaphore.wait()   // wait until tapRunLoop is captured
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

    // Called from CGEventTap thread — must NOT touch MainActor state directly
    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passRetained(event) }
        let keyCode  = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let mods     = event.flags.rawValue & ~CGEventFlags.maskNonCoalesced.rawValue
        let binding  = ShortcutBinding(keyCode: keyCode, modifiers: mods)
        let bindings = self.bindings

        if let zone = bindings[binding] {
            let callback = onZoneTriggered
            DispatchQueue.main.async { callback?(zone) }
            return nil // consume event
        }
        return Unmanaged.passRetained(event)
    }
}
