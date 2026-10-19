import CoreGraphics
import Foundation
import Testing
@testable import tully

struct EventTapServiceTests {
    @Test func firstConsumingHandlerWins() {
        let service = EventTapService()
        let calls = Counter()
        service.add { _, _ in calls.increment(); return false }
        service.add { _, _ in calls.increment(); return true }
        service.add { _, _ in calls.increment(); return true }
        #expect(service.handle(type: .keyDown, event: keyEvent(KeyCode.a)))
        #expect(calls.value == 2)
    }

    @Test func removedHandlerIsNotCalled() {
        let service = EventTapService()
        let id = service.add { _, _ in true }
        service.remove(id)
        #expect(!service.handle(type: .keyDown, event: keyEvent(KeyCode.a)))
    }

    /// Regression for B4: macOS disables slow taps; the service must turn itself back on.
    @Test func reenablesAfterTimeout() {
        let service = EventTapService()
        let reenabled = Counter()
        service.reenable = { reenabled.increment() }
        service.add { _, _ in Issue.record("handlers must not see tap-disabled events"); return true }
        #expect(!service.handle(type: .tapDisabledByTimeout, event: keyEvent(KeyCode.a)))
        #expect(!service.handle(type: .tapDisabledByUserInput, event: keyEvent(KeyCode.a)))
        #expect(reenabled.value == 2)
    }

    @Test func timeoutResetsHandlers() {
        let service = EventTapService()
        let resets = Counter()
        service.add({ _, _ in false }, reset: { resets.increment() })
        _ = service.handle(type: .tapDisabledByTimeout, event: keyEvent(KeyCode.a))
        #expect(resets.value == 1)
    }

    @Test func notRunningUntilStarted() {
        #expect(!EventTapService().isRunning)
    }
}

/// Thread-safe counter for handler callbacks.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
