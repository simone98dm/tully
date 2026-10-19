import AppKit
import ApplicationServices
import CoreGraphics

// Private but long-stable AX SPI (used by every window switcher): maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
nonisolated private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Lists, identifies and raises windows across apps. AX lookups need Accessibility.
enum WindowCatalog {
    private static let axTimeout: Float = 0.25 // seconds; a hung app must not freeze tully
    private static let minimumWindowSide: CGFloat = 60

    /// Normal-layer on-screen windows of other apps, front to back.
    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = pid_t(Foundation.ProcessInfo.processInfo.processIdentifier)
        var seen = Set<CGWindowID>()
        var results: [WindowInfo] = []

        for dict in list {
            guard
                let layer = dict[kCGWindowLayer as String] as? Int32, layer == 0,
                let pidInt = dict[kCGWindowOwnerPID as String] as? Int, pid_t(pidInt) != myPID,
                let widInt = dict[kCGWindowNumber as String] as? Int,
                let appName = dict[kCGWindowOwnerName as String] as? String,
                let alpha = dict[kCGWindowAlpha as String] as? Double, alpha > 0,
                let boundsObj = dict[kCGWindowBounds as String] as? NSDictionary
            else { continue }
            var bounds = CGRect.zero
            CGRectMakeWithDictionaryRepresentation(boundsObj, &bounds)
            guard bounds.width > minimumWindowSide, bounds.height > minimumWindowSide else { continue }

            let wid = CGWindowID(widInt)
            guard seen.insert(wid).inserted else { continue }
            let app = NSRunningApplication(processIdentifier: pid_t(pidInt))
            results.append(WindowInfo(
                id: wid, appName: appName, windowTitle: dict[kCGWindowName as String] as? String ?? "",
                pid: pid_t(pidInt), bundleID: app?.bundleIdentifier, appIcon: app?.icon, frame: bounds
            ))
        }
        return fillingMissingTitles(results)
    }

    /// CGWindowList titles need Screen Recording; fall back to AX titles.
    private static func fillingMissingTitles(_ windows: [WindowInfo]) -> [WindowInfo] {
        let pidsMissingTitles = Set(windows.filter { $0.windowTitle.isEmpty }.map(\.pid))
        guard !pidsMissingTitles.isEmpty, AXIsProcessTrusted() else { return windows }
        var titles: [CGWindowID: String] = [:]
        for pid in pidsMissingTitles {
            for element in axWindows(of: pid) {
                if let id = windowID(of: element), let title = stringAttribute(element, kAXTitleAttribute) {
                    titles[id] = title
                }
            }
        }
        return windows.map { window in
            guard window.windowTitle.isEmpty, let title = titles[window.id] else { return window }
            return WindowInfo(id: window.id, appName: window.appName, windowTitle: title, pid: window.pid,
                              bundleID: window.bundleID, appIcon: window.appIcon, frame: window.frame)
        }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success && id != 0 ? id : nil
    }

    /// The AX element for a window, matched by CGWindowID.
    static func axElement(for window: WindowInfo) -> AXUIElement? {
        axWindows(of: window.pid).first { windowID(of: $0) == window.id }
    }

    static func axWindows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Brings a window to the front. Matching by exact window ID matters: position matching picks
    /// the wrong window when several windows of one app share an origin.
    static func activate(_ window: WindowInfo) {
        let app = NSRunningApplication(processIdentifier: window.pid)
        guard let element = axElement(for: window) ?? axWindows(of: window.pid).first else {
            app?.activate()
            return
        }
        // make it main/focused before activating, or activation brings the previous key window back
        let appElement = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, element)
        // since macOS 14 a background app's activate() may be refused; making it frontmost through
        // Accessibility always works
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app?.activate()
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
