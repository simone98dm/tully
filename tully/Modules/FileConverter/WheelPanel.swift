import AppKit
import KumquatCore

struct WheelItem {
    let id: String
    let label: String
    let symbol: String
}

/// Transparent, non-activating panel that hosts the radial wheel at the cursor and receives the drop.
final class WheelPanel: NSPanel {
    static let size: CGFloat = 340
    let wheelView = WheelView(frame: NSRect(x: 0, y: 0, width: WheelPanel.size, height: WheelPanel.size))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        contentView = wheelView
    }

    func show(kind: WheelKind, items: [WheelItem], fileCount: Int, at point: NSPoint) {
        wheelView.configure(kind: kind, items: items, fileCount: fileCount)
        setFrameOrigin(NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2))
        alphaValue = 1
        orderFrontRegardless()
    }

    func hide() {
        wheelView.highlighted = nil
        orderOut(nil)
    }
}

/// Draws the wheel and acts as the drag destination. Segment 0 at 12 o'clock, clockwise.
final class WheelView: NSView {
    static let maxSegments = 10
    private(set) var items: [WheelItem] = []
    private(set) var kind: WheelKind = .convert
    private var fileCount = 0
    var highlighted: Int? { didSet { if highlighted != oldValue { needsDisplay = true } } }
    /// Called with the chosen item (nil = hub/cancel) and the dropped files.
    var onDrop: ((WheelItem?, [URL], NSPoint) -> Void)?

    var geometry: WheelGeometry {
        WheelGeometry(count: items.count, innerRadius: 46, outerRadius: bounds.width / 2 - 14)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(kind: WheelKind, items all: [WheelItem], fileCount: Int) {
        self.kind = kind
        self.fileCount = fileCount
        // Overflow goes behind a "More…" segment that opens the full list.
        items = all.count > Self.maxSegments
            ? Array(all.prefix(Self.maxSegments - 1)) + [WheelItem(id: "__more", label: "More…", symbol: "ellipsis.circle")]
            : all
        highlighted = nil
        needsDisplay = true
    }

    private var center: NSPoint { NSPoint(x: bounds.midX, y: bounds.midY) }

    func segment(at point: NSPoint) -> Int? {
        geometry.segment(at: CGPoint(x: point.x - center.x, y: point.y - center.y))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let g = geometry
        let outer = g.outerRadius, inner = g.innerRadius
        let accent = NSColor.controlAccentColor
        let base = NSColor.windowBackgroundColor.withAlphaComponent(0.94)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 14
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        base.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)).fill()
        NSGraphicsContext.restoreGraphicsState()

        for (i, item) in items.enumerated() {
            let mid = g.centerAngle(of: i)
            let startDeg = (mid + g.sweep / 2) * 180 / .pi, endDeg = (mid - g.sweep / 2) * 180 / .pi
            let wedge = NSBezierPath()
            wedge.appendArc(withCenter: center, radius: outer - 4, startAngle: startDeg, endAngle: endDeg, clockwise: true)
            wedge.appendArc(withCenter: center, radius: inner + 4, startAngle: endDeg, endAngle: startDeg, clockwise: false)
            wedge.close()
            if i == highlighted {
                accent.setFill()
                wedge.fill()
            }
            if items.count > 1 {
                NSColor.separatorColor.setStroke()
                let line = NSBezierPath()
                let a = mid + g.sweep / 2
                line.move(to: NSPoint(x: center.x + cos(a) * (inner + 4), y: center.y + sin(a) * (inner + 4)))
                line.line(to: NSPoint(x: center.x + cos(a) * (outer - 4), y: center.y + sin(a) * (outer - 4)))
                line.lineWidth = 0.5
                line.stroke()
            }
            drawLabel(item, at: NSPoint(x: center.x + cos(mid) * (inner + outer) / 2, y: center.y + sin(mid) * (inner + outer) / 2),
                      selected: i == highlighted)
        }

        // Hub: cancel target + context.
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - inner + 6, y: center.y - inner + 6, width: (inner - 6) * 2, height: (inner - 6) * 2))
        NSColor.controlBackgroundColor.setFill()
        hub.fill()
        let hubText = items.isEmpty ? "Nothing\navailable" : fileCount > 1 ? "\(kind.title)\n\(fileCount) files" : "\(kind.title)\n✕"
        drawCentered(hubText, at: center, font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)
    }

    private func drawLabel(_ item: WheelItem, at point: NSPoint, selected: Bool) {
        let color: NSColor = selected ? .white : .labelColor
        if let symbol = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.label)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
            let tinted = symbol.tinted(color)
            tinted.draw(in: NSRect(x: point.x - tinted.size.width / 2, y: point.y + 2, width: tinted.size.width, height: tinted.size.height))
        }
        drawCentered(item.label, at: NSPoint(x: point.x, y: point.y - 11), font: .systemFont(ofSize: 10, weight: .semibold), color: color, width: 64)
    }

    /// Wraps to at most two lines within `width`, centered on `point`.
    private func drawCentered(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, width: CGFloat = 90) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        let height = min(attributed.boundingRect(with: NSSize(width: width, height: 60), options: [.usesLineFragmentOrigin]).height, font.pointSize * 2.6)
        attributed.draw(with: NSRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    // MARK: Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // The wheel opens under a still cursor and AppKit reports the entry late: keep any keyboard highlight.
        lastDragLocation = sender.draggingLocation
        if highlighted == nil { highlighted = segment(at: convert(sender.draggingLocation, from: nil)) }
        return .copy
    }

    private var lastDragLocation: NSPoint?

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Periodic updates repeat the same point; only real movement overrides a keyboard highlight.
        if sender.draggingLocation != lastDragLocation {
            lastDragLocation = sender.draggingLocation
            highlighted = segment(at: convert(sender.draggingLocation, from: nil))
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = nil; lastDragLocation = nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let choice = segment(at: convert(sender.draggingLocation, from: nil)).map { items[$0] }
        let screenPoint = window?.convertPoint(toScreen: sender.draggingLocation) ?? NSEvent.mouseLocation
        highlighted = nil
        lastDragLocation = nil
        onDrop?(choice, urls, screenPoint)
        return choice != nil
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let image = copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
