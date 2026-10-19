import AppKit
import KumquatCore

/// Watches system-wide file drags. Tapping a bound modifier mid-drag opens the matching wheel at the cursor.
/// Mouse events can be monitored globally without extra permissions; modifier state is polled.
final class DragMonitor {
    private var session = DragSession()
    private var monitors: [Any] = []
    private var keys = KeyPresses()
    private var pollTimer: Timer?
    private let panel = WheelPanel()
    private var allItems: [WheelItem] = []
    private var dragURLs: [URL] = []
    /// A choice made by keyboard mid-drag waits for mouse-up, or the release would click whatever menu it opened.
    private var pendingChoice: (() -> Void)?
    var onChoose: ((WheelKind, String, [URL], NSPoint) -> Void)?
    var onMore: ((WheelKind, [WheelItem], [URL], NSPoint) -> Void)?

    private static let afterDrop: TimeInterval = 0.2
    private var dragPasteboard: NSPasteboard { NSPasteboard(name: .drag) }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        panel.wheelView.onDrop = { [weak self] item, urls, point in self?.handleDrop(item, urls, point) }
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.mouseDown() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.tick() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() },
        ].compactMap { $0 }
    }

    /// Removes every global monitor and hides the wheel.
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        pollTimer?.invalidate()
        pollTimer = nil
        pendingChoice = nil
        session.dismiss()
        panel.hide()
    }

    private func mouseDown() {
        session.mouseDown(pasteboardChangeCount: dragPasteboard.changeCount)
        // Holding still with a modifier generates no drag events, so poll while the button is down.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func mouseUp() {
        pollTimer?.invalidate()
        pollTimer = nil
        session.mouseUp()
        if let choice = pendingChoice {
            pendingChoice = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterDrop, execute: choice)
        }
        // performDragOperation runs before or right after mouse-up; give it a beat before hiding.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterDrop) { [weak self] in
            if self?.session.visibleWheel == nil { self?.panel.hide() }
        }
    }

    private func tick() {
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }
        pollKeys()
        let pasteboard = dragPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let kind = session.update(pasteboardChangeCount: pasteboard.changeCount, hasFiles: !urls.isEmpty,
                                        flags: NSEvent.modifierFlags, binding: ConverterSettings.shared.binding) else { return }
        dragURLs = urls
        allItems = Self.items(for: kind, urls: urls)
        // Keep the wheel where it first opened when switching kinds mid-drag.
        let origin = panel.isVisible ? NSPoint(x: panel.frame.midX, y: panel.frame.midY) : Self.cursor
        panel.show(kind: kind, items: allItems, fileCount: urls.count, at: origin)
    }

    /// Live cursor from the window server. NSEvent.mouseLocation can lag behind during another app's drag.
    static var cursor: NSPoint {
        guard let point = CGEvent(source: nil)?.location, let primary = NSScreen.screens.first else { return NSEvent.mouseLocation }
        return NSPoint(x: point.x, y: primary.frame.height - point.y)
    }

    static func items(for kind: WheelKind, urls: [URL]) -> [WheelItem] {
        switch kind {
        case .convert:
            return Formats.commonTargets(for: urls).map { WheelItem(id: $0, label: Formats.label(for: $0), symbol: symbol(forTarget: $0)) }
        case .tools:
            // "open in" entries first so they stay on the wheel instead of behind More…
            return FileAction.openIn(for: urls).map { WheelItem(id: $0.rawValue, label: $0.title(for: urls), symbol: $0.symbol) }
                + Tools.applicable(to: urls).map { WheelItem(id: $0.id, label: $0.name, symbol: $0.symbol) }
        case .actions:
            return FileAction.applicable(to: urls).map { WheelItem(id: $0.rawValue, label: $0.title(for: urls), symbol: $0.symbol) }
        }
    }

    static func symbol(forTarget target: String) -> String {
        switch Formats.category(of: URL(fileURLWithPath: "/x.\(target)")) {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .spreadsheet: return "tablecells"
        case .subtitle: return "captions.bubble"
        case .archive: return target == "folder" ? "folder" : "archivebox"
        case .slides: return "rectangle.on.rectangle"
        default: return "doc.text"
        }
    }

    private func handleDrop(_ item: WheelItem?, _ urls: [URL], _ point: NSPoint) {
        let kind = panel.wheelView.kind
        session.dismiss()
        panel.hide()
        guard let item, !urls.isEmpty else { return }
        if item.id == "__more" { deliver { [weak self] in self.map { $0.onMore?(kind, $0.allItems, urls, point) } }; return }
        deliver { [weak self] in self?.onChoose?(kind, item.id, urls, point) }
    }

    /// Runs a choice once the drag is over: a modal or menu opened inside the drop callback would stall
    /// the source app's drag, and one opened under a held mouse would be clicked by the release.
    private func deliver(_ choice: @escaping () -> Void) {
        let choice = { [weak self] in
            // the converter may have been switched off while the choice waited for mouse-up
            guard self?.isRunning == true else { return }
            choice()
        }
        if NSEvent.pressedMouseButtons & 1 == 1 { pendingChoice = choice; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.afterDrop, execute: choice)
    }

    // MARK: Keyboard (arrows / Return / Escape) while the wheel is open

    private static let navigationKeys: [UInt16] = [123, 124, 125, 126, 53, 36, 76]

    /// Key state is polled (like modifiers) because global key-down monitors need Accessibility access.
    private func pollKeys() {
        let down = Set(Self.navigationKeys.filter { CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0)) })
        let pressed = keys.update(down: down)
        guard panel.isVisible else { return }
        pressed.sorted().forEach(key)
    }

    private func key(_ code: UInt16) {
        guard panel.isVisible else { return }
        let view = panel.wheelView
        switch code {
        case 123, 126: view.highlighted = view.geometry.step(from: view.highlighted, by: -1)   // left, up
        case 124, 125: view.highlighted = view.geometry.step(from: view.highlighted, by: 1)    // right, down
        case 53: session.dismiss(); panel.hide()                                               // escape
        case 36, 76:                                                                            // return / enter
            // Enter with nothing highlighted opens the full option list.
            let item = view.highlighted.map { view.items[$0] } ?? WheelItem(id: "__more", label: "", symbol: "")
            handleDrop(item, dragURLs, Self.cursor)
        default: break
        }
    }
}
