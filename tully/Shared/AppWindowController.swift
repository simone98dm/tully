import AppKit
import SwiftUI

/// A regular titled window hosting SwiftUI (Settings, System Monitor, Disk Clean). tully shows in
/// the Dock and ⌘Tab only while at least one of these is open.
final class AppWindowController: NSObject, NSWindowDelegate {
    private static var openCount = 0

    private let identifier: String
    private let title: String
    private let size: CGSize
    private let makeContent: () -> AnyView
    private let isResizable: Bool
    private var window: NSWindow?

    init(identifier: String, title: String, size: CGSize, resizable: Bool = true, content: @escaping () -> AnyView) {
        self.identifier = identifier
        self.isResizable = resizable
        self.title = title
        self.size = size
        self.makeContent = content
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        let window = window ?? makeWindow()
        if !window.isVisible {
            Self.openCount += 1
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless() // activation is only a request since macOS 14
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        Self.openCount = max(0, Self.openCount - 1)
        if Self.openCount == 0 { NSApp.setActivationPolicy(.accessory) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: isResizable ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                                   : [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: makeContent())
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("tully.\(identifier)")
        self.window = window
        return window
    }
}
