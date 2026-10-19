import AppKit
import ApplicationServices

@Observable
final class WindowManagerService {
    static let shortcutsKey = "tully.windowManager.shortcuts"
    static let legacyShortcutsKey = "com.mymenu.shortcuts"

    static let autoLayoutKey = "tully.windowManager.autoLayout"
    static let autoLayoutDelayKey = "tully.windowManager.autoLayoutDelay"
    static let autoLayoutDelays: [Double] = [3, 6, 10, 20]

    private(set) var isPermissionGranted = false
    private(set) var shortcuts: [String: ShortcutBinding] = [:]

    /// After snapping to a side, suggest other windows for the space that's left.
    var isAutoLayoutEnabled: Bool {
        didSet { defaults.set(isAutoLayoutEnabled, forKey: Self.autoLayoutKey) }
    }
    /// Seconds the suggestions stay up without interaction.
    var autoLayoutDelay: Double {
        didSet { defaults.set(autoLayoutDelay, forKey: Self.autoLayoutDelayKey) }
    }

    /// Called after every snap (zone shortcut or ring) with the window, its new frame and screen.
    @ObservationIgnored var onSnap: ((AXUIElement, CGRect, NSScreen) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let eventTap: EventTapService?
    @ObservationIgnored private let handler = KeyboardShortcutHandler()
    @ObservationIgnored private var tapHandlerID: UUID?

    init(defaults: UserDefaults = .standard, eventTap: EventTapService? = nil) {
        self.defaults = defaults
        self.eventTap = eventTap
        isAutoLayoutEnabled = defaults.object(forKey: Self.autoLayoutKey) as? Bool ?? true
        let delay = defaults.double(forKey: Self.autoLayoutDelayKey)
        autoLayoutDelay = Self.autoLayoutDelays.contains(delay) ? delay : 6
        shortcuts = Self.loadShortcuts(from: defaults)
        handler.onZoneTriggered = { [weak self] zone in
            MainActor.assumeIsolated { self?.moveFocusedWindow(to: zone) }
        }
        rebuildHandlerBindings()
    }

    /// Starts or stops listening for shortcuts as Accessibility access comes and goes.
    func updatePermission(_ granted: Bool) {
        isPermissionGranted = granted
        if granted, tapHandlerID == nil, let eventTap {
            let handler = handler
            tapHandlerID = eventTap.add { type, event in handler.handle(type: type, event: event) }
        } else if !granted, let id = tapHandlerID {
            eventTap?.remove(id)
            tapHandlerID = nil
        }
    }

    // MARK: - Shortcuts

    /// Assigning a combo another zone uses moves it here (the recorder asks first).
    func setShortcut(_ binding: ShortcutBinding?, for zone: WindowZone) {
        if let binding {
            shortcuts = shortcuts.filter { $0.value != binding }
            shortcuts[zone.rawValue] = binding
        } else {
            shortcuts.removeValue(forKey: zone.rawValue)
        }
        saveShortcuts()
        rebuildHandlerBindings()
    }

    func conflictingZone(for binding: ShortcutBinding, excluding zone: WindowZone) -> WindowZone? {
        shortcuts.first(where: { $0.key != zone.rawValue && $0.value == binding })
            .flatMap { WindowZone(rawValue: $0.key) }
    }

    func reset() {
        shortcuts = [:]
        isAutoLayoutEnabled = true
        autoLayoutDelay = 6
        [Self.shortcutsKey, Self.autoLayoutKey, Self.autoLayoutDelayKey].forEach(defaults.removeObject(forKey:))
        rebuildHandlerBindings()
    }

    // MARK: - Moving windows

    func moveFocusedWindow(to zone: WindowZone) {
        guard isPermissionGranted, let window = Self.focusedWindow() else { return }
        move(window, to: zone, on: Self.screen(of: window))
    }

    /// Moves `window` into `zone` of `screen` and reports the snap.
    func move(_ window: AXUIElement, to zone: WindowZone, on screen: NSScreen) {
        let target = zone.frame(in: screen.visibleFrame)
        Self.apply(target, to: window)
        onSnap?(window, target, screen)
    }

    static func focusedWindow() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success, let app = focusedApp else { return nil }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success, let window = focusedWindow else { return nil }
        return (window as! AXUIElement)
    }

    /// AX frame (top-left origin) of a window.
    static func axFrame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    /// The screen holding most of the window (multi-monitor safe).
    static func screen(of window: AXUIElement) -> NSScreen {
        let screens = NSScreen.screens
        let fallback = NSScreen.main ?? screens[0]
        guard let axFrame = axFrame(of: window), let primary = screens.first else { return fallback }
        let rect = ScreenGeometry.appKitRect(fromAX: axFrame, primaryHeight: primary.frame.height)
        return ScreenGeometry.bestScreenIndex(for: rect, screens: screens.map(\.frame)).map { screens[$0] } ?? fallback
    }

    /// Moves and resizes an AX window to `nsFrame` (AppKit coordinates).
    static func apply(_ nsFrame: CGRect, to window: AXUIElement) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? nsFrame.maxY
        var axOrigin = ScreenGeometry.axOrigin(forAppKit: nsFrame, primaryHeight: primaryHeight)
        var axSize = nsFrame.size

        // size → position → size: avoids clamping when moving to a smaller display
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &axOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    // MARK: - Private

    private func rebuildHandlerBindings() {
        var map: [ShortcutBinding: WindowZone] = [:]
        for zone in WindowZone.allCases {
            if let binding = shortcuts[zone.rawValue] { map[binding] = zone }
        }
        handler.bindings = map
    }

    private func saveShortcuts() {
        guard let encoded = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(encoded, forKey: Self.shortcutsKey)
    }

    /// Reads current shortcuts, copying the pre-v2 key once. The old key is kept so an older
    /// installed version sharing the same defaults keeps working.
    static func loadShortcuts(from defaults: UserDefaults) -> [String: ShortcutBinding] {
        if let data = defaults.data(forKey: shortcutsKey) {
            return (try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)) ?? [:]
        }
        guard let legacy = defaults.data(forKey: legacyShortcutsKey),
              let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: legacy)
        else { return [:] }
        defaults.set(legacy, forKey: shortcutsKey)
        return decoded
    }
}
