import Testing
@testable import tully

@MainActor
struct KeyboardCleaningTests {
    final class FakeTap {
        var started = 0
        var stopped = 0
    }

    func makeService(trusted: Bool = true, tapStarts: Bool = true) -> (KeyboardCleaningService, FakeTap) {
        let fake = FakeTap()
        let service = KeyboardCleaningService(
            defaults: makeDefaults(), isTrusted: { trusted },
            startBlocking: { fake.started += 1; return tapStarts },
            stopBlocking: { fake.stopped += 1 },
            showsOverlay: false, tick: .milliseconds(1)
        )
        return (service, fake)
    }

    @Test func startsAndStops() {
        let (service, tap) = makeService()
        #expect(service.setEnabled(true))
        #expect(service.isEnabled && tap.started == 1)
        #expect(service.secondsRemaining == service.autoExitSeconds)
        service.setEnabled(false)
        #expect(!service.isEnabled && tap.stopped == 1)
    }

    @Test func needsAccessibilityAndAWorkingTap() {
        #expect(!makeService(tapStarts: false).0.setEnabled(true))
        let (untrusted, tap) = makeService(trusted: false)
        _ = untrusted // opening System Settings is a side effect we can't assert; the tap must not start
        #expect(tap.started == 0)
    }

    @Test func autoExitTurnsTheKeyboardBackOn() async throws {
        let (service, tap) = makeService()
        service.autoExitSeconds = 30 // 30 ticks of 1 ms
        service.setEnabled(true)
        for _ in 0..<200 where service.isEnabled { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!service.isEnabled)
        #expect(tap.stopped == 1)
    }

    @Test func autoExitSettingPersists() {
        let defaults = makeDefaults()
        let service = KeyboardCleaningService(defaults: defaults, showsOverlay: false)
        #expect(service.autoExitSeconds == 60)
        service.autoExitSeconds = 120
        #expect(KeyboardCleaningService(defaults: defaults, showsOverlay: false).autoExitSeconds == 120)
    }
}

@MainActor
struct PreventSleepTests {
    @Test func holdsAssertionOnlyWhileEnabled() {
        let service = PreventSleepService(defaults: makeDefaults())
        #expect(!service.hasActiveAssertion)
        service.setEnabled(true)
        #expect(service.isEnabled && service.hasActiveAssertion)
        service.setEnabled(false)
        #expect(!service.isEnabled && !service.hasActiveAssertion)
    }

    @Test func timeoutTurnsItOff() async throws {
        let service = PreventSleepService(defaults: makeDefaults())
        service.setEnabled(true)
        service.scheduleEnd(after: 0.05)
        #expect(service.endsAt != nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!service.isEnabled && !service.hasActiveAssertion)
    }

    @Test func switchingModeKeepsOneAssertion() {
        let service = PreventSleepService(defaults: makeDefaults())
        service.setEnabled(true)
        service.keepsDisplayAwake.toggle()
        #expect(service.isEnabled && service.hasActiveAssertion)
        service.setEnabled(false)
        #expect(!service.hasActiveAssertion)
    }

    @Test func settingsPersist() {
        let defaults = makeDefaults()
        let service = PreventSleepService(defaults: defaults)
        service.keepsDisplayAwake = false
        service.duration = .oneHour
        let reloaded = PreventSleepService(defaults: defaults)
        #expect(!reloaded.keepsDisplayAwake && reloaded.duration == .oneHour && !reloaded.isEnabled)
    }
}
