import AppKit
import ApplicationServices

/// Tracks the privacy permissions tully needs and notices when the user grants or revokes them,
/// so features start without a relaunch.
@Observable
final class PermissionCenter {
    struct Checker {
        var accessibility: () -> Bool
        var screenRecording: () -> Bool

        static let live = Checker(
            accessibility: { AXIsProcessTrusted() },
            screenRecording: { CGPreflightScreenCaptureAccess() }
        )
    }

    static let pollInterval: TimeInterval = 2

    private(set) var isAccessibilityGranted: Bool
    private(set) var isScreenRecordingGranted: Bool

    @ObservationIgnored private let checker: Checker
    @ObservationIgnored private var listeners: [(PermissionCenter) -> Void] = []
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(checker: Checker = .live) {
        self.checker = checker
        isAccessibilityGranted = checker.accessibility()
        isScreenRecordingGranted = checker.screenRecording()
    }

    var allGranted: Bool { isAccessibilityGranted && isScreenRecordingGranted }

    /// Called once now and again whenever a permission changes.
    func observe(_ listener: @escaping (PermissionCenter) -> Void) {
        listeners.append(listener)
        listener(self)
    }

    func refresh() {
        let accessibility = checker.accessibility()
        let screenRecording = checker.screenRecording()
        guard accessibility != isAccessibilityGranted || screenRecording != isScreenRecordingGranted else { return }
        isAccessibilityGranted = accessibility
        isScreenRecordingGranted = screenRecording
        listeners.forEach { $0(self) }
    }

    /// Re-checks on app activation, and polls only while Accessibility is missing (the call is cheap).
    func startMonitoring() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isAccessibilityGranted else { return }
                self.refresh()
            }
        }
    }

    static func openSettings(_ pane: Pane) {
        NSWorkspace.shared.open(pane.url)
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
        case fullDiskAccess = "Privacy_AllFiles"

        var url: URL { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")! }
    }
}
