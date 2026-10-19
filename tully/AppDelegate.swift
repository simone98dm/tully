import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var launchWindows: [NSWindow] = []
    private var appearanceObservation: NSKeyValueObservation?
    /// What the status item currently shows; identical redraws are skipped.
    private var renderedStatus: StatusRenderKey?

    let eventTap = EventTapService()
    let permissions = PermissionCenter()
    let monitor = SystemMonitorService(defaults: AppEnvironment.defaults)
    let diskScanner = DiskScanService()
    lazy var diskClean = DiskCleanService(defaults: AppEnvironment.defaults)
    lazy var keyboardCleaning = KeyboardCleaningService(defaults: AppEnvironment.defaults)
    lazy var preventSleep = PreventSleepService(defaults: AppEnvironment.defaults)
    lazy var converter = FileConverterController()
    let settings = AppSettings(defaults: AppEnvironment.defaults)
    let popoverState = PopoverState()
    let toasts = ToastCenter()
    lazy var windowManager = WindowManagerService(defaults: AppEnvironment.defaults, eventTap: eventTap)
    lazy var tabSwitch = TabSwitchService(defaults: AppEnvironment.defaults, eventTap: eventTap)
    lazy var autoLayout = AutoLayoutController(eventTap: eventTap)
    lazy var windowRing = WindowRingService(defaults: AppEnvironment.defaults, eventTap: eventTap, windowManager: windowManager)
    let settingsState = SettingsState()
    private lazy var settingsWindow = AppWindowController(identifier: "settings", title: "tully Settings",
                                                          size: SettingsView.minSize) { [unowned self] in
        AnyView(self.withServices(SettingsView()).environment(self.settingsState))
    }
    private lazy var systemMonitorWindow = AppWindowController(identifier: "systemMonitor", title: "System Monitor",
                                                               size: CGSize(width: 960, height: 680)) { [unowned self] in
        AnyView(self.withServices(SystemMonitorWindowView()))
    }
    private lazy var aboutWindow = AppWindowController(identifier: "about", title: "About tully",
                                                       size: AboutView.size, resizable: false) { [unowned self] in
        AnyView(self.withServices(AboutView()))
    }
    private lazy var diskCleanWindow = AppWindowController(identifier: "diskClean", title: "Disk Clean",
                                                           size: CGSize(width: 720, height: 620)) { [unowned self] in
        AnyView(self.withServices(DiskCleanView()))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningUnitTests else { return }
        if let scene = AppEnvironment.value(for: "--show-scene"), let window = ScreenshotRenderer.showScene(scene) {
            launchWindows.append(window)
            NSApp.activate()
            return
        }
        if let dir = AppEnvironment.value(for: "--render-screenshots") {
            do { try ScreenshotRenderer.run(to: URL(fileURLWithPath: dir)) } catch { NSLog("tully: screenshots failed: \(error)") }
            exit(0)
        }
        KeyboardLayout.refresh()
        NSApp.applicationIconImage = AppIcon.image // Dock/⌘Tab while a window is open, despite cached icons
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { KeyboardLayout.refresh() } }
        permissions.observe { [weak self] permissions in self?.permissionsChanged(permissions) }
        permissions.startMonitoring()

        let overlayPanel = TabSwitchOverlayWindow()
        overlayPanel.contentViewController = NSHostingController(
            rootView: TabSwitchOverlayView().environment(tabSwitch)
        )
        tabSwitch.overlayPanel = overlayPanel

        popoverState.open = { [weak self] destination in self?.open(destination) }
        setUpStatusItem()
        setUpPopover()

        windowManager.onSnap = { [weak self] window, frame, screen in
            guard let self, self.windowManager.isAutoLayoutEnabled else { return }
            self.autoLayout.dismissDelay = .seconds(self.windowManager.autoLayoutDelay)
            self.autoLayout.offer(after: window, frame: frame, on: screen)
        }
        monitor.onSample = { [weak self] _ in self?.updateStatusItem() }
        monitor.needsDetails = { [weak self] in
            guard let self else { return false }
            return self.popover.isShown || self.systemMonitorWindow.isVisible || !self.launchWindows.isEmpty
        }
        settings.onChange = { [weak self] in self?.updateStatusItem() }
        if AppEnvironment.usesDemoData { DemoData.fill(monitor, disk: diskScanner, settings: settings) } else { monitor.start() }
        // UI tests must not install global drag monitors or pop up onboarding
        if !AppEnvironment.isUITesting && !AppEnvironment.usesDemoData { converter.apply() }
        observeModes()
        updateStatusItem()
        openWindowsRequestedByLaunchFlags()
    }

    func applicationWillTerminate(_ notification: Notification) {
        preventSleep.setEnabled(false)
        keyboardCleaning.setEnabled(false)
        eventTap.stop()
    }

    private func permissionsChanged(_ permissions: PermissionCenter) {
        let accessibility = permissions.isAccessibilityGranted && !AppEnvironment.isUITesting
        if accessibility { eventTap.start() } else { eventTap.stop() }
        // ring first: its trigger + arrow keys win over a zone shortcut on the same keys (Settings warns)
        windowRing.updatePermission(accessibility)
        windowManager.updatePermission(accessibility)
        tabSwitch.updatePermissions(accessibility: accessibility, screenRecording: permissions.isScreenRecordingGranted)
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(statusItemClicked)
        button.target = self
        button.imagePosition = .imageOnly
        // tinted (non-template) images must be redrawn when the menu bar turns light/dark;
        // setting the image also fires this, so updateStatusItem ignores unchanged state
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let segments = StatusBarFormatter.segments(for: monitor.snapshot, metrics: settings.visibleMetrics)
        let badges = statusBadges
        let key = StatusRenderKey(segments: segments, style: settings.statusStyle, tinted: settings.tintsHighUsage,
                                  badges: badges,
                                  isDark: button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        guard key != renderedStatus else { return }
        renderedStatus = key
        let icon = NSImage(named: "MenuIcon")
        button.image = StatusBarRenderer.image(
            segments: segments, style: settings.statusStyle, icon: icon,
            tinted: settings.tintsHighUsage, appearance: button.effectiveAppearance, badges: badges
        )
        var label = StatusBarFormatter.accessibilityLabel(for: segments)
        if preventSleep.isEnabled { label += ", staying awake" }
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    private var statusBadges: [String] {
        var badges: [String] = []
        if preventSleep.isEnabled { badges.append("cup.and.saucer.fill") }
        if keyboardCleaning.isEnabled { badges.append("keyboard.badge.ellipsis") }
        return badges
    }

    /// Redraws the status item whenever an observed mode changes.
    private func observeModes() {
        withObservationTracking {
            _ = preventSleep.isEnabled
            _ = keyboardCleaning.isEnabled
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.observeModes()
            }
        }
    }

    @objc private func statusItemClicked() {
        // no current event when pressed via Accessibility (VoiceOver) — treat as left click
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            togglePopover()
            return
        }
        let menu = NSMenu()
        menu.addItem(menuItem("Open tully", #selector(togglePopover), key: "", symbol: "menubar.rectangle"))
        let converterItems = converter.menuItems()
        if !converterItems.isEmpty {
            converterItems.forEach(menu.addItem)
            menu.addItem(.separator())
        }
        menu.addItem(menuItem("System Monitor…", #selector(openSystemMonitor), key: "", symbol: "chart.xyaxis.line"))
        menu.addItem(menuItem("Disk Clean…", #selector(openDiskClean), key: "", symbol: "trash"))
        menu.addItem(menuItem("Settings…", #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(menuItem("About tully", #selector(showAbout), key: "", symbol: "info.circle"))
        menu.addItem(menuItem("Quit tully", #selector(NSApplication.terminate(_:)), key: "q", symbol: "power", target: NSApp))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, key: String, symbol: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func showAbout() { open(.about) }

    @objc private func openSettings() { open(.settings(nil)) }
    @objc private func openSystemMonitor() { open(.systemMonitor) }
    @objc private func openDiskClean() { open(.diskClean) }

    private func open(_ destination: PopoverState.Destination) {
        popover.performClose(nil)
        switch destination {
        case .settings(let section):
            if let section { settingsState.section = section }
            settingsWindow.show()
        case .systemMonitor:
            systemMonitorWindow.show()
        case .diskClean:
            diskCleanWindow.show()
        case .about:
            aboutWindow.show()
        }
    }

    // MARK: - Popover

    private func setUpPopover() {
        popover = NSPopover()
        popover.contentSize = ContentView.size
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    private var rootView: some View {
        withServices(ContentView())
    }

    /// Injects every shared service into a SwiftUI root.
    private func withServices(_ view: some View) -> some View {
        view
            .environment(popoverState)
            .environment(toasts)
            .environment(permissions)
            .environment(monitor)
            .environment(diskScanner)
            .environment(diskClean)
            .environment(keyboardCleaning)
            .environment(preventSleep)
            .environment(converter)
            .environment(windowManager)
            .environment(windowRing)
            .environment(tabSwitch)
            .environment(settings)
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// UI tests can't click menu bar extras reliably, so they ask for the popover content in a window.
    private func openWindowsRequestedByLaunchFlags() {
        if let pane = AppEnvironment.value(for: "--open-settings") {
            open(.settings(SettingsSection(rawValue: pane)))
        }
        if AppEnvironment.value(for: "--open-system-monitor") != nil { open(.systemMonitor) }
        if AppEnvironment.value(for: "--open-disk-clean") != nil { open(.diskClean) }
        if AppEnvironment.value(for: "--open-about") != nil { open(.about) }
        guard let tab = AppEnvironment.value(for: "--open-popover-window") else { return }
        if let index = AppTab.allCases.first(where: { $0.title.lowercased() == tab.lowercased() }) { popoverState.select(index) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ContentView.size),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "tully"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: rootView)
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        launchWindows.append(window)
    }
}

private struct StatusRenderKey: Equatable {
    let segments: [StatusSegment]
    let style: StatusStyle
    let tinted: Bool
    let badges: [String]
    let isDark: Bool
}
