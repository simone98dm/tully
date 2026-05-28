// tully/Modules/TabSwitch/TabSwitchService.swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

@Observable
final class TabSwitchService {
    var isEnabled: Bool = false
    var hotkey: ShortcutBinding? = nil
    var isPermissionGranted: Bool = false
    var hasScreenRecordingPermission: Bool = false

    private(set) var windows: [WindowInfo] = []
    var selectedIndex: Int = 0

    private let handler = TabHotkeyHandler()
    var overlayPanel: TabSwitchOverlayWindow?

    private let defaultsKey = "com.tully.tabswitch"

    func setup() {
        isPermissionGranted = AXIsProcessTrusted()
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        handler.onActivate = { [weak self] in self?.showOverlay() }
        handler.onTab      = { [weak self] shift in self?.cycleSelection(reverse: shift) }
        handler.onConfirm  = { [weak self] in self?.confirmSelection() }
        handler.onDismiss  = { [weak self] in self?.dismissOverlay() }

        loadSettings()
        if isEnabled, hotkey != nil { startListening() }
    }

    func teardown() { handler.stop() }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        saveSettings()
        if value { startListening() } else { stopListening() }
    }

    func setHotkey(_ binding: ShortcutBinding?) {
        hotkey = binding
        saveSettings()
        if isEnabled { stopListening(); startListening() }
    }

    func reset() {
        setEnabled(false)
        setHotkey(nil)
    }

    // MARK: - Overlay Lifecycle

    func showOverlay() {
        windows = enumerateWindows()
        selectedIndex = min(1, max(0, windows.count - 1))
        handler.isOverlayVisible = true
        positionOverlay()
        overlayPanel?.orderFrontRegardless()
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
        let win = windows[selectedIndex]
        raiseWindow(pid: win.pid, windowID: win.id)
        dismissOverlay()
    }

    func cycleSelection(reverse: Bool) {
        guard !windows.isEmpty else { return }
        let n = windows.count
        selectedIndex = reverse ? (selectedIndex - 1 + n) % n : (selectedIndex + 1) % n
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

    private func startListening() {
        guard let hk = hotkey else { return }
        handler.hotkey = hk
        handler.start()
    }

    private func stopListening() { handler.stop() }

    private func enumerateWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = pid_t(Foundation.ProcessInfo.processInfo.processIdentifier)
        var seen = Set<CGWindowID>()
        var results: [WindowInfo] = []

        for dict in list {
            guard
                let layer    = dict[kCGWindowLayer as String] as? Int32, layer == 0,
                let pidInt   = dict[kCGWindowOwnerPID as String] as? Int, pid_t(pidInt) != myPID,
                let widInt   = dict[kCGWindowNumber as String] as? Int,
                let appName  = dict[kCGWindowOwnerName as String] as? String,
                let alpha    = dict[kCGWindowAlpha as String] as? Double, alpha > 0,
                let bounds   = dict[kCGWindowBounds as String] as? [String: CGFloat],
                (bounds["Width"] ?? 0) > 60,
                (bounds["Height"] ?? 0) > 60
            else { continue }

            let wid = CGWindowID(widInt)
            guard seen.insert(wid).inserted else { continue }

            let title = dict[kCGWindowName as String] as? String ?? ""
            let icon = NSRunningApplication(processIdentifier: pid_t(pidInt))?.icon
            results.append(WindowInfo(id: wid, appName: appName, windowTitle: title, pid: pid_t(pidInt), appIcon: icon))
        }
        return results
    }

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

    private func raiseWindow(pid: pid_t, windowID: CGWindowID) {
        let appEl = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement]
        else {
            NSRunningApplication(processIdentifier: pid)?.activate()
            return
        }

        // Match by position: kCGWindowBounds and kAXPositionAttribute both use
        // top-left-origin screen coordinates, so they're directly comparable.
        let targetOrigin = cgOriginForWindow(windowID)
        var bestWindow: AXUIElement? = nil

        if let target = targetOrigin {
            var bestDist = CGFloat.infinity
            for axWin in axWindows {
                var posRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
                      let pv = posRef else { continue }
                var axPos = CGPoint.zero
                AXValueGetValue(pv as! AXValue, .cgPoint, &axPos)
                let dist = abs(axPos.x - target.x) + abs(axPos.y - target.y)
                if dist < bestDist {
                    bestDist = dist
                    bestWindow = axWin
                }
            }
        }

        let win = bestWindow ?? axWindows.first
        if let win {
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            // kAXMainAttribute = "AXMain" — marks this window as the key window of the app
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    private func cgOriginForWindow(_ windowID: CGWindowID) -> CGPoint? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow], windowID
        ) as? [[String: Any]],
        let dict = list.first,
        let boundsObj = dict[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        var rect = CGRect.zero
        CGRectMakeWithDictionaryRepresentation(boundsObj, &rect)
        return rect.width > 0 ? rect.origin : nil
    }

    // MARK: - Persistence

    private func loadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: defaultsKey + ".enabled")
        if let data = UserDefaults.standard.data(forKey: defaultsKey + ".hotkey"),
           let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) {
            hotkey = decoded
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: defaultsKey + ".enabled")
        if let hk = hotkey, let encoded = try? JSONEncoder().encode(hk) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey + ".hotkey")
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey + ".hotkey")
        }
    }
}
