import CoreGraphics

/// Coordinate conversions between the Accessibility API (top-left origin, y down, anchored to the
/// primary screen) and AppKit (bottom-left origin, y up). Pure so it can be tested without screens.
nonisolated enum ScreenGeometry {
    static func appKitRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axOrigin(forAppKit rect: CGRect, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryHeight - rect.maxY)
    }

    /// Index of the screen that holds most of `rect` (AppKit coordinates); falls back to the screen
    /// nearest to its center when it overlaps none.
    static func bestScreenIndex(for rect: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(rect)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screens.indices.min { distance(screens[$0], center) < distance(screens[$1], center) }
    }

    static func screenIndex(containing point: CGPoint, screens: [CGRect]) -> Int? {
        screens.firstIndex { $0.contains(point) }
            ?? screens.indices.min { distance(screens[$0], point) < distance(screens[$1], point) }
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
