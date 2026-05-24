// tully/Modules/WindowManager/WindowManagerService.swift
import AppKit
import ApplicationServices

@Observable
final class WindowManagerService {
    var isPermissionGranted: Bool = false
    var shortcuts: [String: ShortcutBinding] = [:]

    private let defaultsKey = "com.mymenu.shortcuts"

    func setup() {
        isPermissionGranted = AXIsProcessTrusted()
        loadShortcuts()
    }

    func moveActiveWindow(to zone: WindowZone) {
        guard isPermissionGranted else { return }

        let systemElement = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemElement, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success, let app = focusedApp else { return }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            (app as! AXUIElement), kAXFocusedWindowAttribute as CFString, &focusedWindow
        ) == .success, let window = focusedWindow else { return }

        let windowElement = window as! AXUIElement
        let screen = screenForWindow(windowElement)
        let targetFrame = frame(for: zone, on: screen)
        applyFrame(targetFrame, to: windowElement, screen: screen)
    }

    func setShortcut(_ binding: ShortcutBinding?, for zone: WindowZone) {
        if let binding {
            shortcuts[zone.rawValue] = binding
        } else {
            shortcuts.removeValue(forKey: zone.rawValue)
        }
        saveShortcuts()
    }

    func conflictingZone(for binding: ShortcutBinding, excluding zone: WindowZone) -> WindowZone? {
        shortcuts.first(where: { $0.key != zone.rawValue && $0.value == binding })
            .flatMap { WindowZone(rawValue: $0.key) }
    }

    // MARK: - Private

    private func screenForWindow(_ window: AXUIElement) -> NSScreen {
        var positionValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue)
        var position = CGPoint.zero
        if let pv = positionValue { AXValueGetValue(pv as! AXValue, .cgPoint, &position) }
        return NSScreen.screens.first { $0.frame.contains(position) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func frame(for zone: WindowZone, on screen: NSScreen) -> CGRect {
        let f = zone == .fullscreen ? screen.frame : screen.visibleFrame
        switch zone {
        case .leftHalf:       return CGRect(x: f.minX,              y: f.minY, width: f.width / 2,     height: f.height)
        case .rightHalf:      return CGRect(x: f.midX,              y: f.minY, width: f.width / 2,     height: f.height)
        case .leftThird:      return CGRect(x: f.minX,              y: f.minY, width: f.width / 3,     height: f.height)
        case .centerThird:    return CGRect(x: f.minX + f.width/3,  y: f.minY, width: f.width / 3,     height: f.height)
        case .rightThird:     return CGRect(x: f.minX + 2*f.width/3,y: f.minY, width: f.width / 3,     height: f.height)
        case .leftTwoThirds:  return CGRect(x: f.minX,              y: f.minY, width: 2*f.width / 3,   height: f.height)
        case .rightTwoThirds: return CGRect(x: f.minX + f.width/3,  y: f.minY, width: 2*f.width / 3,   height: f.height)
        case .fullscreen:     return f
        case .topLeft:        return CGRect(x: f.minX,              y: f.midY, width: f.width / 2,     height: f.height / 2)
        case .topRight:       return CGRect(x: f.midX,              y: f.midY, width: f.width / 2,     height: f.height / 2)
        case .bottomLeft:     return CGRect(x: f.minX,              y: f.minY, width: f.width / 2,     height: f.height / 2)
        case .bottomRight:    return CGRect(x: f.midX,              y: f.minY, width: f.width / 2,     height: f.height / 2)
        }
    }

    private func applyFrame(_ nsFrame: CGRect, to window: AXUIElement, screen: NSScreen) {
        // AX uses top-left origin; NSScreen uses bottom-left origin.
        // Primary screen height anchors the coordinate flip.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let axY = primaryHeight - nsFrame.maxY

        var axOrigin = CGPoint(x: nsFrame.minX, y: axY)
        var axSize   = CGSize(width: nsFrame.width, height: nsFrame.height)

        if let posVal = AXValueCreate(.cgPoint, &axOrigin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)
        else { return }
        shortcuts = decoded
    }

    private func saveShortcuts() {
        guard let encoded = try? JSONEncoder().encode(shortcuts) else { return }
        UserDefaults.standard.set(encoded, forKey: defaultsKey)
    }
}
