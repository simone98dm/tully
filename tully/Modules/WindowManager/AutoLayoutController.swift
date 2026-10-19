import AppKit
import SwiftUI

/// After a window snaps to a side, offers the other open windows to fill the space that's left.
/// Mouse: click a row. Keyboard (only while shown): ↑↓ to choose, Return to place, Esc to dismiss.
@Observable
final class AutoLayoutController {
    nonisolated static let maxCandidates = 8

    private(set) var candidates: [WindowInfo] = []
    private(set) var highlighted = 0

    @ObservationIgnored var dismissDelay: Duration = .seconds(6)
    @ObservationIgnored private var target: CGRect = .zero // AppKit coordinates
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let eventTap: EventTapService?
    @ObservationIgnored private var keyHandlerID: UUID?
    @ObservationIgnored private var appSwitchObserver: NSObjectProtocol?

    init(eventTap: EventTapService?) {
        self.eventTap = eventTap
    }

    var isVisible: Bool { !candidates.isEmpty }

    func offer(after snappedWindow: AXUIElement, frame: CGRect, on screen: NSScreen) {
        dismiss() // a new move replaces any suggestion still showing
        guard let remainder = FreeSpace.remainder(after: frame, in: screen.visibleFrame) else { return }
        let snappedID = WindowCatalog.windowID(of: snappedWindow)
        let windows = WindowCatalog.onScreenWindows()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let otherFrames = windows.filter { $0.id != snappedID }
            .map { ScreenGeometry.appKitRect(fromAX: $0.frame, primaryHeight: primaryHeight) }
        // the other half is already in use (e.g. a window tiled there): nothing to fill
        guard Self.isFree(remainder, avoiding: otherFrames) else { return }
        let others = Self.candidates(from: windows, excluding: snappedID, on: screen.frame)
        guard !others.isEmpty else { return }
        present(others, in: remainder)
    }

    /// A window is "tiled into" the free space when it fills most of it and sits mostly inside it.
    nonisolated static let fillsThreshold = 0.8
    nonisolated static let insideThreshold = 0.8

    /// True unless another window is already tiled into `rect`. Large windows that merely lie
    /// behind it (e.g. a maximized browser) don't count.
    nonisolated static func isFree(_ rect: CGRect, avoiding windows: [CGRect]) -> Bool {
        let area = rect.width * rect.height
        guard area > 0 else { return false }
        return !windows.contains { window in
            let overlap = rect.intersection(window)
            guard !overlap.isNull, window.width * window.height > 0 else { return false }
            let overlapArea = overlap.width * overlap.height
            return overlapArea / area >= fillsThreshold && overlapArea / (window.width * window.height) >= insideThreshold
        }
    }

    /// Windows that can fill the space: not the snapped one, on the same screen, at most `maxCandidates`.
    nonisolated static func candidates(from windows: [WindowInfo], excluding snappedID: CGWindowID?,
                                       on screenFrame: CGRect, primaryHeight: CGFloat? = nil) -> [WindowInfo] {
        let height = primaryHeight ?? NSScreen.screens.first?.frame.height ?? 0
        return Array(windows.filter { window in
            window.id != snappedID
                && screenFrame.intersects(ScreenGeometry.appKitRect(fromAX: window.frame, primaryHeight: height))
        }.prefix(maxCandidates))
    }

    func choose(_ window: WindowInfo) {
        let frame = target
        dismiss() // before activating, so the app switch doesn't race the dismissal
        guard let element = WindowCatalog.axElement(for: window) else { return }
        WindowManagerService.apply(frame, to: element)
        WindowCatalog.activate(window)
    }

    func moveHighlight(by delta: Int) {
        guard !candidates.isEmpty else { return }
        highlighted = (highlighted + delta + candidates.count) % candidates.count
        restartDismissTimer()
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let keyHandlerID { eventTap?.remove(keyHandlerID) }
        keyHandlerID = nil
        if let appSwitchObserver { NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver) }
        appSwitchObserver = nil
        dismissTask?.cancel()
        panel?.orderOut(nil)
        candidates = []
        highlighted = 0
    }

    /// Shows the list; internal so tests can drive it without real windows.
    func present(_ windows: [WindowInfo], in rect: CGRect) {
        candidates = windows
        highlighted = 0
        target = rect
        let panel = panel ?? makePanel()
        panel.setFrame(rect.insetBy(dx: 8, dy: 8), display: true)
        panel.orderFrontRegardless()
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: "Fill this space: \(windows.count) windows. Use arrow keys and Return."])

        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        registerKeys()
        // switching apps with the keyboard (⌘Tab, the switcher) means the suggestion is no longer wanted
        if appSwitchObserver == nil {
            appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.processIdentifier != Foundation.ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }
        restartDismissTimer()
    }

    /// Fills the list without showing a panel (screenshots).
    func loadCandidatesForScreenshot(_ windows: [WindowInfo]) {
        candidates = windows
        highlighted = 0
    }

    private func registerKeys() {
        guard keyHandlerID == nil, let eventTap else { return }
        keyHandlerID = eventTap.add { [weak self] type, event in
            // plain keys only: ⌘↑ or Return with modifiers in another app must pass through
            guard type == .keyDown,
                  event.flags.rawValue & ShortcutBinding.userModifiers.rawValue == 0,
                  event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            guard [125, 126, 36, 76, 53].contains(key) else { return false }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch key {
                    case 125: self.moveHighlight(by: 1)
                    case 126: self.moveHighlight(by: -1)
                    case 36, 76: if self.candidates.indices.contains(self.highlighted) { self.choose(self.candidates[self.highlighted]) }
                    default: self.dismiss()
                    }
                }
            }
            return true
        }
    }

    private func restartDismissTimer() {
        dismissTask?.cancel()
        let delay = dismissDelay
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel()
        panel.hasShadow = false
        panel.level = .floating
        panel.contentView = FirstMouseHostingView(rootView: AutoLayoutView().environment(self))
        self.panel = panel
        return panel
    }
}

struct AutoLayoutView: View {
    @Environment(AutoLayoutController.self) private var controller

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 2))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Fill this space with…", systemImage: "rectangle.split.2x1")
                    .font(.headline)
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(controller.candidates.enumerated()), id: \.element.id) { index, window in
                    row(window, isHighlighted: index == controller.highlighted)
                }
                Text("Click or use ↑↓ and Return · Esc or click elsewhere to dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            .padding(16)
            .frame(maxWidth: 380)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
    }

    private func row(_ window: WindowInfo, isHighlighted: Bool) -> some View {
        Button { controller.choose(window) } label: {
            HStack(spacing: 10) {
                if let icon = window.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 26, height: 26).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName).lineLimit(1)
                    if !window.windowTitle.isEmpty {
                        Text(window.windowTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isHighlighted {
                    Image(systemName: "return").foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHighlighted ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityLabel("\(window.appName) \(window.windowTitle)")
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
