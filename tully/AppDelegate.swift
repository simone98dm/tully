// tully/AppDelegate.swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    let monitor = SystemMonitorService()
    let diskScanner = DiskScanService()
    let windowManager = WindowManagerService()
    let tabSwitch = TabSwitchService()
    let settings = AppSettings()
    private var statusUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor.start()
        windowManager.setup()
        tabSwitch.setup()

        // Build Tab Switch overlay panel once; service shows/hides it as needed
        let overlayPanel = TabSwitchOverlayWindow()
        overlayPanel.contentViewController = NSHostingController(
            rootView: TabSwitchOverlayView()
                .environment(tabSwitch)
        )
        tabSwitch.overlayPanel = overlayPanel

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon = NSImage(named: "MenuIcon") {
                icon.isTemplate = true
                button.image = icon
            }
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environment(monitor)
                .environment(diskScanner)
                .environment(windowManager)
                .environment(tabSwitch)
                .environment(settings)
        )

        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.updateStatusBarText()
        }
        updateStatusBarText()
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "About tully…", action: #selector(showAbout), keyEquivalent: ""))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit tully", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "tully"
        alert.informativeText = """
            A lightweight macOS menu bar app for system monitoring and window management.

            github.com/simone98dm/tully

            © 2026 simone98dm
            """
        alert.icon = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
        alert.addButton(withTitle: "Close")
        alert.runModal()
    }

    private func updateStatusBarText() {
        guard let button = statusItem.button else { return }
        let snap = monitor.snapshot
        var parts: [String] = []

        if settings.showCPU {
            parts.append(String(format: "%.0f%%", snap.cpuPercent))
        }
        if settings.showRAM {
            parts.append(String(format: "%.1fGB", Double(snap.ramUsed) / 1_073_741_824.0))
        }
        if settings.showNet {
            let bps = max(0.0, snap.netIn)
            if bps >= 1_048_576 {
                parts.append(String(format: "↓%.1fMB/s", bps / 1_048_576))
            } else if bps >= 1024 {
                parts.append(String(format: "↓%.0fKB/s", bps / 1024))
            } else {
                parts.append("↓\(Int(bps))B/s")
            }
        }

        let text = parts.joined(separator: " · ")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        ]
        if text.isEmpty {
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.imagePosition = .imageRight
            // trailing space separates text from icon on the right
            button.attributedTitle = NSAttributedString(string: text + " ", attributes: attrs)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
