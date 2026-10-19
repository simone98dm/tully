import AppKit
import ApplicationServices
import CoreGraphics

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let appName: String
    let windowTitle: String
    let pid: pid_t
    var bundleID: String?
    var appIcon: NSImage?
    var thumbnail: NSImage?
    /// Top-left-origin global frame (CGWindowList coordinates).
    var frame: CGRect = .zero
}
