import AppKit

/// Draws the menu bar item: stat segments (fixed-width slots) followed by the app icon.
enum StatusBarRenderer {
    static let height: CGFloat = 22
    private static let symbolSize: CGFloat = 11
    private static let spacing: CGFloat = 6
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let stackedLabelFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private static let stackedValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    /// - Parameter tinted: colour segments above the warning threshold. Tinted images can't be
    ///   templates, so they're drawn for the given appearance instead.
    /// - Parameter badges: SF Symbols drawn before the icon for active modes (e.g. Prevent Sleep).
    static func image(segments: [StatusSegment], style: StatusStyle, icon: NSImage?,
                      tinted: Bool, appearance: NSAppearance, badges: [String] = []) -> NSImage {
        let usesTint = tinted && segments.contains { $0.level != .normal }
        let slots = segments.map { slotWidth(for: $0, style: style) }
        let badgeImages = badges.compactMap { symbolImage($0, color: usesTint ? .labelColor : .black) }
        let badgesWidth = badgeImages.reduce(0) { $0 + $1.size.width + 3 }
        let iconWidth = (icon?.size.width ?? 0) + badgesWidth
        let statsWidth = slots.reduce(0, +) + spacing * CGFloat(max(0, slots.count - 1))
        let width = statsWidth + (segments.isEmpty ? 0 : spacing) + iconWidth

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                var x: CGFloat = 0
                for (segment, slot) in zip(segments, slots) {
                    let color = usesTint ? color(for: segment.level) : .black
                    draw(segment, style: style, in: NSRect(x: x, y: 0, width: slot, height: height), color: color)
                    x += slot + spacing
                }
                var badgeX = width - iconWidth
                for badge in badgeImages {
                    badge.draw(in: NSRect(x: badgeX, y: (height - badge.size.height) / 2,
                                          width: badge.size.width, height: badge.size.height))
                    badgeX += badge.size.width + 3
                }
                if let icon {
                    let rect = NSRect(x: width - icon.size.width, y: (height - icon.size.height) / 2,
                                      width: icon.size.width, height: icon.size.height)
                    tintedIcon(icon, color: usesTint ? .labelColor : .black).draw(in: rect)
                }
            }
            return true
        }
        image.isTemplate = !usesTint
        return image
    }

    private static func color(for level: UsageLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .elevated: .systemOrange
        case .critical: .systemRed
        }
    }

    private static func slotWidth(for segment: StatusSegment, style: StatusStyle) -> CGFloat {
        let valueWidth = max(textWidth(segment.metric.widthTemplate, font: valueFont), textWidth(segment.value, font: valueFont))
        switch style {
        case .iconValue: return symbolSize + 3 + valueWidth
        case .labelValue: return textWidth(segment.metric.shortLabel + " ", font: valueFont) + valueWidth
        case .compact: return valueWidth
        case .stacked:
            return max(textWidth(segment.metric.shortLabel, font: stackedLabelFont),
                       textWidth(segment.metric.widthTemplate, font: stackedValueFont),
                       textWidth(segment.value, font: stackedValueFont))
        }
    }

    private static func draw(_ segment: StatusSegment, style: StatusStyle, in rect: NSRect, color: NSColor) {
        switch style {
        case .iconValue:
            if let symbol = symbolImage(segment.metric.symbol, color: color) {
                symbol.draw(in: NSRect(x: rect.minX, y: (height - symbol.size.height) / 2,
                                       width: symbol.size.width, height: symbol.size.height))
            }
            drawText(segment.value, font: valueFont, color: color, at: rect.minX + symbolSize + 3, in: rect)
        case .labelValue:
            let label = segment.metric.shortLabel + " "
            drawText(label, font: valueFont, color: color.withAlphaComponent(0.7), at: rect.minX, in: rect)
            drawText(segment.value, font: valueFont, color: color, at: rect.minX + textWidth(label, font: valueFont), in: rect)
        case .compact:
            drawText(segment.value, font: valueFont, color: color, at: rect.minX, in: rect)
        case .stacked:
            let top = NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
            let bottom = NSRect(x: rect.minX, y: 0, width: rect.width, height: rect.height / 2 + 1)
            drawText(segment.metric.shortLabel, font: stackedLabelFont, color: color.withAlphaComponent(0.7), centeredIn: top)
            drawText(segment.value, font: stackedValueFont, color: color, centeredIn: bottom)
        }
    }

    private static func symbolImage(_ name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    private static func tintedIcon(_ icon: NSImage, color: NSColor) -> NSImage {
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, centeredIn rect: NSRect) {
        drawText(text, font: font, color: color, at: rect.midX - textWidth(text, font: font) / 2, in: rect)
    }

    private static func drawText(_ text: String, font: NSFont, color: NSColor, at x: CGFloat, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: x, y: rect.minY + (rect.height - size.height) / 2), withAttributes: attributes)
    }
}
