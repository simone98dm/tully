// tully/Modules/TabSwitch/TabSwitchService.swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

@Observable
final class TabSwitchService {
    private(set) var isEnabled: Bool = false
    private(set) var hotkey: ShortcutBinding? = nil
    private(set) var isPermissionGranted: Bool = false
    private(set) var hasScreenRecordingPermission: Bool = false

    private(set) var windows: [WindowInfo] = []
    var selectedIndex: Int = 0

    @ObservationIgnored var overlayPanel: TabSwitchOverlayWindow?

    @ObservationIgnored private let handler = TabHotkeyHandler()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let eventTap: EventTapService?
    @ObservationIgnored private var tapHandlerID: UUID?

    static let defaultsKey = "com.tully.tabswitch"

    init(defaults: UserDefaults = .standard, eventTap: EventTapService? = nil) {
        self.defaults = defaults
        self.eventTap = eventTap
        handler.onActivate = { [weak self] in MainActor.assumeIsolated { self?.showOverlay() } }
        handler.onTab      = { [weak self] shift in MainActor.assumeIsolated { self?.cycleSelection(reverse: shift) } }
        handler.onConfirm  = { [weak self] in MainActor.assumeIsolated { self?.confirmSelection() } }
        handler.onDismiss  = { [weak self] in MainActor.assumeIsolated { self?.dismissOverlay() } }
        handler.onQuit     = { [weak self] in MainActor.assumeIsolated { self?.quitSelectedApp() } }
        loadSettings()
    }

    func updatePermissions(accessibility: Bool, screenRecording: Bool) {
        isPermissionGranted = accessibility
        hasScreenRecordingPermission = screenRecording
        updateListening()
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        saveSettings()
        updateListening()
    }

    func setHotkey(_ binding: ShortcutBinding?) {
        hotkey = binding
        saveSettings()
        updateListening()
    }

    func reset() {
        setEnabled(false)
        setHotkey(nil)
    }

    // MARK: - Overlay Lifecycle

    /// `list` overrides window enumeration (tests).
    func showOverlay(with list: [WindowInfo]? = nil) {
        windows = list ?? enumerateWindows()
        selectedIndex = min(1, max(0, windows.count - 1))
        handler.isOverlayVisible = true
        positionOverlay()
        overlayPanel?.orderFrontRegardless()
        // the modifier may have been released before the overlay appeared (a quick tap): switch right away
        // NSEvent.modifierFlags is stale while tully is in the background; ask the window server
        if list == nil, let hotkey, hotkey.modifiers != 0,
           CGEventSource.flagsState(.combinedSessionState).rawValue & hotkey.modifiers == 0 {
            confirmSelection()
            return
        }
        Task { await captureThumbnails() }
    }

    func dismissOverlay() {
        handler.isOverlayVisible = false
        overlayPanel?.orderOut(nil)
        windows = []
        selectedIndex = 0
    }

    func confirmSelection() {
        guard selectedIndex < windows.count else { dismissOverlay(); return }
        WindowCatalog.activate(windows[selectedIndex])
        dismissOverlay()
    }

    func cycleSelection(reverse: Bool) {
        guard !windows.isEmpty else { return }
        let n = windows.count
        selectedIndex = reverse ? (selectedIndex - 1 + n) % n : (selectedIndex + 1) % n
    }

    /// Quits the selected window's app and drops all its windows from the list; the overlay stays open.
    /// `terminate` is injectable for tests.
    func quitSelectedApp(terminate: (pid_t) -> Void = { NSRunningApplication(processIdentifier: $0)?.terminate() }) {
        guard selectedIndex < windows.count else { return }
        let pid = windows[selectedIndex].pid
        guard pid != getpid() else { return }
        terminate(pid)
        let removedBefore = windows[..<selectedIndex].filter { $0.pid == pid }.count
        windows = windows.filter { $0.pid != pid }
        guard !windows.isEmpty else { dismissOverlay(); return }
        selectedIndex = min(selectedIndex - removedBefore, windows.count - 1)
        positionOverlay()
    }

    // MARK: - Private

    private func positionOverlay() {
        guard let panel = overlayPanel, let screen = NSScreen.main else { return }
        let n = max(windows.count, 1)
        let cols = CGFloat(min(n, 6))
        let rows = CGFloat(ceil(Double(n) / 6.0))
        let cardW: CGFloat = 196
        let cardH: CGFloat = 162
        let gap: CGFloat = 12
        let w = cols * cardW + (cols - 1) * gap + 48   // 24px padding each side
        let h = rows * cardH + (rows - 1) * gap + 32   // 16px padding each side
        panel.setFrame(
            NSRect(x: screen.frame.midX - w / 2, y: screen.frame.midY - h / 2, width: w, height: h),
            display: false
        )
    }

    private func updateListening() {
        handler.hotkey = hotkey
        let shouldListen = isEnabled && hotkey != nil && isPermissionGranted
        if shouldListen, tapHandlerID == nil, let eventTap {
            let handler = handler
            tapHandlerID = eventTap.add({ type, event in handler.handle(type: type, event: event) }, reset: { handler.reset() })
        } else if !shouldListen, let id = tapHandlerID {
            eventTap?.remove(id)
            tapHandlerID = nil
            if handler.isOverlayVisible { dismissOverlay() }
        }
    }

    private func enumerateWindows() -> [WindowInfo] { WindowCatalog.onScreenWindows() }

    private func captureThumbnails() async {
        guard CGPreflightScreenCaptureAccess() else { return }
        let snapshot = windows
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for win in snapshot {
                guard let scWin = content.windows.first(where: { $0.windowID == win.id }) else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: scWin)
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 200
                config.scalesToFit = true
                guard let cg = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config
                ) else { continue }
                let img = NSImage(cgImage: cg, size: NSSize(width: 320, height: 200))
                if let idx = self.windows.firstIndex(where: { $0.id == win.id }) {
                    self.windows[idx].thumbnail = img
                }
            }
        } catch {
            // screen capture unavailable — thumbnails remain nil
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        isEnabled = defaults.bool(forKey: Self.defaultsKey + ".enabled")
        if let data = defaults.data(forKey: Self.defaultsKey + ".hotkey"),
           let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            hotkey = decoded
        }
    }

    private func saveSettings() {
        defaults.set(isEnabled, forKey: Self.defaultsKey + ".enabled")
        if let hk = hotkey, let encoded = try? JSONEncoder().encode(hk) {
            defaults.set(encoded, forKey: Self.defaultsKey + ".hotkey")
        } else {
            defaults.removeObject(forKey: Self.defaultsKey + ".hotkey")
        }
    }
}
