import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac (and optionally the display) awake with an IOKit power assertion.
@Observable
final class PreventSleepService {
    enum Duration: Int, CaseIterable, Identifiable {
        case untilTurnedOff = 0, fifteenMinutes = 900, oneHour = 3600, twoHours = 7200

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .untilTurnedOff: "Until turned off"
            case .fifteenMinutes: "15 minutes"
            case .oneHour: "1 hour"
            case .twoHours: "2 hours"
            }
        }
    }

    static let displayKey = "tully.preventSleep.display"
    static let durationKey = "tully.preventSleep.duration"
    static let assertionName = "tully: Prevent Sleep"

    // ponytail: isEnabled is not persisted — a forgotten "never sleep" surviving relaunch drains batteries
    private(set) var isEnabled = false
    private(set) var endsAt: Date?

    /// true: display stays on too. false: only the Mac stays awake.
    var keepsDisplayAwake: Bool {
        didSet {
            defaults.set(keepsDisplayAwake, forKey: Self.displayKey)
            if isEnabled { recreateAssertion() }
        }
    }
    var duration: Duration {
        didSet { defaults.set(duration.rawValue, forKey: Self.durationKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var assertionID: IOPMAssertionID = 0
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        keepsDisplayAwake = defaults.object(forKey: Self.displayKey) as? Bool ?? true
        duration = Duration(rawValue: defaults.integer(forKey: Self.durationKey)) ?? .untilTurnedOff
    }

    func setEnabled(_ value: Bool) {
        guard value != isEnabled else { return }
        if value {
            isEnabled = createAssertion()
            guard isEnabled else { return }
            scheduleEnd(after: duration == .untilTurnedOff ? nil : TimeInterval(duration.rawValue))
        } else {
            releaseAssertion()
            timer?.cancel()
            timer = nil
            endsAt = nil
            isEnabled = false
        }
    }

    /// Ends after `seconds` (nil: never). Internal so tests can use short timeouts.
    func scheduleEnd(after seconds: TimeInterval?) {
        timer?.cancel()
        guard let seconds else { endsAt = nil; return }
        endsAt = Date().addingTimeInterval(seconds)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.setEnabled(false)
        }
    }

    /// Whether tully currently holds its assertion (read back from IOKit).
    var hasActiveAssertion: Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let byProcess = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]],
              let mine = byProcess[NSNumber(value: getpid())]
        else { return false }
        return mine.contains { ($0[kIOPMAssertionNameKey] as? String) == Self.assertionName }
    }

    private func createAssertion() -> Bool {
        let type = keepsDisplayAwake ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep
        return IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           Self.assertionName as CFString, &assertionID) == kIOReturnSuccess
    }

    private func releaseAssertion() {
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
    }

    private func recreateAssertion() {
        releaseAssertion()
        isEnabled = createAssertion()
    }
}
