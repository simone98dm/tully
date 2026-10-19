import AppKit
import ApplicationServices
import SwiftUI

nonisolated private let NX_SYSDEFINED: UInt32 = 14 // media / brightness / volume keys

nonisolated private func keyboardBlockCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let tap = Unmanaged<KeyboardBlockTap>.fromOpaque(userInfo).takeUnretainedValue()
            tap.reenable()
        }
        return Unmanaged.passUnretained(event)
    }
    return nil // swallow every keyboard event
}

/// Event tap that swallows all keyboard input (keys, modifiers, media keys) on the main run loop.
nonisolated final class KeyboardBlockTap: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << NX_SYSDEFINED)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keyboardBlockCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reenable() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}

/// Disables the keyboard so it can be wiped. Exit with the mouse ("Done"), or automatically after
/// `autoExitSeconds` so nobody gets locked out.
@Observable
final class KeyboardCleaningService {
    static let autoExitKey = "tully.keyboardCleaning.autoExit"
    static let autoExitChoices: [Int] = [30, 60, 120, 300]

    private(set) var isEnabled = false
    private(set) var secondsRemaining = 0
    var autoExitSeconds: Int {
        didSet { defaults.set(autoExitSeconds, forKey: Self.autoExitKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let isTrusted: () -> Bool
    @ObservationIgnored private let startBlocking: () -> Bool
    @ObservationIgnored private let stopBlocking: () -> Void
    @ObservationIgnored private let showsOverlay: Bool
    @ObservationIgnored private let tick: Duration
    @ObservationIgnored private var overlay: NSPanel?
    @ObservationIgnored private var countdown: Task<Void, Never>?

    /// The closures are injectable so tests never block the real keyboard.
    init(defaults: UserDefaults = .standard,
         isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         tap: KeyboardBlockTap = KeyboardBlockTap(),
         startBlocking: (() -> Bool)? = nil,
         stopBlocking: (() -> Void)? = nil,
         showsOverlay: Bool = true,
         tick: Duration = .seconds(1)) {
        self.defaults = defaults
        self.isTrusted = isTrusted
        self.startBlocking = startBlocking ?? { tap.start() }
        self.stopBlocking = stopBlocking ?? { tap.stop() }
        self.showsOverlay = showsOverlay
        self.tick = tick
        let saved = defaults.integer(forKey: Self.autoExitKey)
        autoExitSeconds = Self.autoExitChoices.contains(saved) ? saved : 60
    }

    /// Returns false when Accessibility is missing (and opens its settings).
    @discardableResult
    func setEnabled(_ value: Bool) -> Bool {
        guard value != isEnabled else { return true }
        if value { return start() }
        stop()
        return true
    }

    private func start() -> Bool {
        guard isTrusted() else {
            PermissionCenter.openSettings(.accessibility)
            return false
        }
        guard startBlocking() else { return false }
        isEnabled = true
        secondsRemaining = autoExitSeconds
        if showsOverlay { showOverlay() }
        let tick = tick
        countdown = Task { [weak self] in
            while let self, self.secondsRemaining > 0 {
                try? await Task.sleep(for: tick)
                guard !Task.isCancelled else { return }
                self.secondsRemaining -= 1
            }
            self?.stop()
        }
        return true
    }

    private func stop() {
        countdown?.cancel()
        countdown = nil
        stopBlocking()
        isEnabled = false
        secondsRemaining = 0
        overlay?.orderOut(nil)
        overlay = nil
    }

    private func showOverlay() {
        guard let screen = NSScreen.main else { return }
        let panel = FloatingPanel()
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.contentView = FirstMouseHostingView(rootView: KeyboardCleaningOverlayView().environment(self))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        overlay = panel
    }
}

struct KeyboardCleaningOverlayView: View {
    @Environment(KeyboardCleaningService.self) private var service

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 14) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 48, weight: .light))
                    .accessibilityHidden(true)
                Text("Keyboard Cleaning")
                    .font(.title2.weight(.semibold))
                Text("Your keyboard is disabled. Clean away, then click Done.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Turns back on automatically in \(service.secondsRemaining) s")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Keyboard turns back on in \(service.secondsRemaining) seconds")
                Button("Done") { service.setEnabled(false) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .pointerStyle(.link)
            }
            .padding(36)
            .frame(width: 380)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }
}
