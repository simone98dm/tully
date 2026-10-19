import AppKit
import SwiftUI

/// Hold the trigger (default ⌃⌥, user-configurable) to show a
/// ring at the cursor where moving the mouse picks a zone, previewed on screen, applied on release.
@Observable
final class WindowRingService {
    enum RingSize: String, CaseIterable, Identifiable {
        case small, medium, large
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var diameter: CGFloat {
            switch self {
            case .small: 150
            case .medium: 190
            case .large: 240
            }
        }
    }

    static let defaultTrigger: CGEventFlags = [.maskControl, .maskAlternate]
    static let holdThreshold: TimeInterval = 0.15
    private static let trackingInterval: TimeInterval = 1.0 / 60

    private enum Key {
        static let ringEnabled = "tully.ring.enabled"
        static let trigger = "tully.ring.trigger"
        static let preview = "tully.ring.preview"
        static let size = "tully.ring.size"
        static let haptics = "tully.ring.haptics"
        static let legacyArrows = "tully.ring.arrows" // removed feature; cleared on reset
        static let all = [ringEnabled, legacyArrows, trigger, preview, size, haptics]
    }

    // MARK: Settings

    var isRingEnabled: Bool { didSet { save(isRingEnabled, Key.ringEnabled) } }
    /// Modifier combination that opens the ring.
    var trigger: CGEventFlags {
        didSet {
            save(trigger.rawValue, Key.trigger)
            handler.trigger = trigger
        }
    }
    var showsPreview: Bool { didSet { save(showsPreview, Key.preview) } }
    var ringSize: RingSize { didSet { save(ringSize.rawValue, Key.size) } }
    var usesHaptics: Bool { didSet { save(usesHaptics, Key.haptics) } }

    // MARK: Ring state

    private(set) var isRingVisible = false
    private(set) var highlightedZone: WindowZone?
    var hubRadius: CGFloat { ringSize.diameter * 0.18 }
    var outerRadius: CGFloat { ringSize.diameter * 0.5 + 40 }

    @ObservationIgnored let handler: RingKeyHandler
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let eventTap: EventTapService?
    @ObservationIgnored private let windowManager: WindowManagerService
    @ObservationIgnored private var tapHandlerID: UUID?
    @ObservationIgnored private var ringPanel: NSPanel?
    @ObservationIgnored private var previewPanel: NSPanel?
    @ObservationIgnored private var trackingTimer: Timer?
    @ObservationIgnored private var ringCenter: CGPoint = .zero
    @ObservationIgnored private var targetWindow: AXUIElement?

    init(defaults: UserDefaults = .standard, eventTap: EventTapService?, windowManager: WindowManagerService) {
        self.defaults = defaults
        self.eventTap = eventTap
        self.windowManager = windowManager
        let savedTrigger = CGEventFlags(rawValue: (defaults.object(forKey: Key.trigger) as? UInt64) ?? 0)
            .intersection(ShortcutBinding.userModifiers)
        let trigger = savedTrigger.isEmpty ? Self.defaultTrigger : savedTrigger
        handler = RingKeyHandler(trigger: trigger)
        self.trigger = trigger
        isRingEnabled = defaults.object(forKey: Key.ringEnabled) as? Bool ?? true
        showsPreview = defaults.object(forKey: Key.preview) as? Bool ?? true
        ringSize = defaults.string(forKey: Key.size).flatMap(RingSize.init) ?? .medium
        usesHaptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        handler.onSignal = { [weak self] signal in MainActor.assumeIsolated { self?.handle(signal) } }
    }

    var triggerDisplay: String { ShortcutBinding.modifierSymbols(trigger) }

    func updatePermission(_ granted: Bool) {
        if granted, tapHandlerID == nil, let eventTap {
            let handler = handler
            tapHandlerID = eventTap.add({ type, event in handler.handle(type: type, event: event) }, reset: { handler.reset() })
        } else if !granted, let id = tapHandlerID {
            eventTap?.remove(id)
            tapHandlerID = nil
            hideRing()
        }
    }

    func reset() {
        Key.all.forEach(defaults.removeObject(forKey:))
        isRingEnabled = true
        trigger = Self.defaultTrigger
        showsPreview = true
        ringSize = .medium
        usesHaptics = true
        Key.all.forEach(defaults.removeObject(forKey:))
    }

    /// Shows a highlighted segment without tracking the mouse (screenshots).
    func highlightForScreenshot(_ zone: WindowZone) { highlightedZone = zone }

    // MARK: Signals

    func handle(_ signal: RingKeyHandler.Signal) {
        switch signal {
        case .triggerDown:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isRingEnabled, self.handler.mayShowRing else { return }
                    self.showRing()
                }
            }
        case .triggerUp(let apply):
            if apply, isRingVisible, let zone = highlightedZone { applyRing(zone) }
            hideRing()
        case .cancel:
            hideRing()
        }
    }

    // MARK: Ring

    private func showRing() {
        guard !isRingVisible, windowManager.isPermissionGranted, let window = WindowManagerService.focusedWindow() else { return }
        targetWindow = window
        ringCenter = NSEvent.mouseLocation
        highlightedZone = nil
        isRingVisible = true
        handler.isRingVisible = true

        let panel = ringPanel ?? makePanel(RingView().environment(self))
        ringPanel = panel
        let side = ringSize.diameter + 60
        panel.setFrame(NSRect(x: ringCenter.x - side / 2, y: ringCenter.y - side / 2, width: side, height: side), display: true)
        panel.orderFrontRegardless()

        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: Self.trackingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let zone = RingLogic.zone(for: CGVector(dx: mouse.x - ringCenter.x, dy: mouse.y - ringCenter.y),
                                  hubRadius: hubRadius, outerRadius: outerRadius)
        guard zone != highlightedZone else { return }
        highlightedZone = zone
        if usesHaptics, zone != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        updatePreview()
    }

    private func updatePreview() {
        guard showsPreview, let zone = highlightedZone else {
            previewPanel?.orderOut(nil)
            return
        }
        let frame = zone.frame(in: Self.screenUnderCursor().visibleFrame)
        let panel = previewPanel ?? makePanel(RingPreviewView())
        previewPanel = panel
        panel.level = .floating
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && panel.isVisible)
        panel.orderFrontRegardless()
        ringPanel?.orderFrontRegardless()
    }

    private func applyRing(_ zone: WindowZone) {
        guard let window = targetWindow else { return }
        windowManager.move(window, to: zone, on: Self.screenUnderCursor())
        announce(zone)
    }

    private func hideRing() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        ringPanel?.orderOut(nil)
        previewPanel?.orderOut(nil)
        isRingVisible = false
        handler.isRingVisible = false
        highlightedZone = nil
        targetWindow = nil
    }

    private func announce(_ zone: WindowZone) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Window moved to \(zone.displayName)"])
    }

    /// Fling across displays: the target screen is the one under the cursor.
    static func screenUnderCursor() -> NSScreen {
        let screens = NSScreen.screens
        let index = ScreenGeometry.screenIndex(containing: NSEvent.mouseLocation, screens: screens.map(\.frame))
        return index.map { screens[$0] } ?? NSScreen.main ?? screens[0]
    }

    private func makePanel(_ view: some View) -> NSPanel {
        let panel = FloatingPanel()
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: view)
        return panel
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
