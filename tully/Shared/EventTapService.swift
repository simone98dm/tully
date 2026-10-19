import CoreGraphics
import Foundation

// File-scope C callback; runs on the tap thread.
nonisolated private func sharedTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<EventTapService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

/// One session event tap (keyDown, keyUp, flagsChanged) on a dedicated thread, shared by every
/// keyboard feature. Handlers run on the tap thread: they must be quick and must not touch MainActor
/// state directly. A handler returns true to consume the event.
nonisolated final class EventTapService: @unchecked Sendable {
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Bool

    static let eventMask = CGEventMask(
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)
    )

    private let lock = NSLock()
    private var handlers: [(id: UUID, handler: Handler, reset: (@Sendable () -> Void)?)] = []
    private var _reenable: @Sendable () -> Void = {}
    private var eventTap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var selfUnmanaged: Unmanaged<EventTapService>?
    /// Re-enables the tap after macOS disables it (slow handler or secure input). Injectable for tests.
    var reenable: @Sendable () -> Void {
        get { lock.withLock { _reenable } }
        set { lock.withLock { _reenable = newValue } }
    }

    var isRunning: Bool { lock.withLock { eventTap != nil } }

    /// - Parameter reset: called after macOS disabled and re-enabled the tap. Key and modifier events
    ///   may have been missed meanwhile, so handlers drop any "held" state.
    @discardableResult
    func add(_ handler: @escaping Handler, reset: (@Sendable () -> Void)? = nil) -> UUID {
        let id = UUID()
        lock.withLock { handlers.append((id, handler, reset)) }
        return id
    }

    func remove(_ id: UUID) {
        lock.withLock { handlers.removeAll { $0.id == id } }
    }

    /// Needs Accessibility permission; returns false when the tap can't be created.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let unmanaged = Unmanaged.passRetained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.eventMask,
            callback: sharedTapCallback,
            userInfo: unmanaged.toOpaque()
        ) else {
            unmanaged.release()
            return false
        }
        // CF types aren't Sendable; they're handed to the tap thread once and only used there
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        nonisolated(unsafe) let threadTap = tap
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            self?.lock.withLock { self?.tapRunLoop = runLoop }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: threadTap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.tully.eventtap"
        lock.withLock {
            eventTap = tap
            selfUnmanaged = unmanaged
            tapThread = thread
        }
        nonisolated(unsafe) let reenableTap = tap
        reenable = { CGEvent.tapEnable(tap: reenableTap, enable: true) }
        thread.start()
        ready.wait()
        return true
    }

    func stop() {
        let (tap, runLoop, unmanaged) = lock.withLock { (eventTap, tapRunLoop, selfUnmanaged) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
        lock.withLock {
            eventTap = nil
            tapRunLoop = nil
            tapThread = nil
            selfUnmanaged = nil
        }
        reenable = {}
        unmanaged?.release()
    }

    /// Dispatches one event to the handlers in registration order. Internal for tests.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            lock.withLock { handlers.compactMap(\.reset) }.forEach { $0() }
            return false
        }
        let current = lock.withLock { handlers.map(\.handler) }
        return current.contains { $0(type, event) }
    }
}
