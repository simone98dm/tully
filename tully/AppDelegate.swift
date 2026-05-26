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
    let updater = UpdaterService()

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
        )
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "About tully…", action: #selector(showAbout), keyEquivalent: ""))
            menu.addItem(.separator())
            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            menu.addItem(updateItem)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit tully", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
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
