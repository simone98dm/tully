import AppKit
import QuickLookThumbnailing

/// "Float": parks files in a small always-on-top shelf so they can be dragged out later.
final class FloatPanel: NSPanel {
    private static var open: [FloatPanel] = []
    private let urls: [URL]

    static func show(_ urls: [URL], near point: NSPoint) {
        let panel = FloatPanel(urls: urls)
        let offset = CGFloat(open.count) * 24
        panel.setFrameOrigin(NSPoint(x: point.x - 70 + offset, y: point.y - 70 - offset))
        panel.orderFrontRegardless()
        open.append(panel)
    }

    init(urls: [URL]) {
        self.urls = urls
        super.init(contentRect: NSRect(x: 0, y: 0, width: 140, height: 150), styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .hudWindow],
                   backing: .buffered, defer: false)
        title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = FloatView(urls: urls)
    }

    override func close() {
        super.close()
        Self.open.removeAll { $0 === self }
    }
}

/// Thumbnail that is a drag source for its files. Closes the shelf after a successful move/copy out.
final class FloatView: NSView, NSDraggingSource {
    private let urls: [URL]
    private let imageView = NSImageView()

    init(urls: [URL]) {
        self.urls = urls
        super.init(frame: NSRect(x: 0, y: 0, width: 140, height: 128))
        imageView.frame = bounds.insetBy(dx: 14, dy: 10)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSWorkspace.shared.icon(forFiles: urls.map(\.path))
        imageView.unregisterDraggedTypes()
        addSubview(imageView)
        setAccessibilityLabel("Floating \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"), drag to use")
        let request = QLThumbnailGenerator.Request(fileAt: urls[0], size: CGSize(width: 220, height: 220), scale: 2, representationTypes: .thumbnail)
        if urls.count == 1 {
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
                guard let image = rep?.nsImage else { return }
                DispatchQueue.main.async { self?.imageView.image = image }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        let items = urls.enumerated().map { i, url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let frame = imageView.frame.offsetBy(dx: CGFloat(i) * 4, dy: CGFloat(-i) * 4)
            item.setDraggingFrame(frame, contents: i == 0 ? imageView.image : IconCache.icon(forFile: url.path))
            return item
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { window?.close() }
    }
}
