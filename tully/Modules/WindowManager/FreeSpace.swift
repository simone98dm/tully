import CoreGraphics

/// Finds the empty area around a point, between other windows — used by ⌘-drag "snap into available space".
nonisolated enum FreeSpace {
    static let minimumSize = CGSize(width: 200, height: 150)

    /// The largest rectangle inside `bounds` that contains `point` and overlaps none of `obstacles`,
    /// or nil when the point is covered or the space is too small to be useful.
    static func rect(containing point: CGPoint, in bounds: CGRect, avoiding obstacles: [CGRect]) -> CGRect? {
        guard bounds.contains(point), !obstacles.contains(where: { $0.contains(point) }) else { return nil }

        // ponytail: greedy — trim nearest obstacles first, each by the cut that keeps the most area.
        // Exact for tiled layouts; heavily overlapping free-floating windows can yield a smaller rect than optimal.
        let sorted = obstacles.sorted { distance($0, point) < distance($1, point) }
        var rect = bounds
        for obstacle in sorted {
            let overlap = rect.intersection(obstacle)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }

            var candidates: [CGRect] = []
            if overlap.maxX <= point.x { candidates.append(rect.divided(atDistance: overlap.maxX - rect.minX, from: .minXEdge).remainder) }
            if overlap.minX >= point.x { candidates.append(rect.divided(atDistance: overlap.minX - rect.minX, from: .minXEdge).slice) }
            if overlap.maxY <= point.y { candidates.append(rect.divided(atDistance: overlap.maxY - rect.minY, from: .minYEdge).remainder) }
            if overlap.minY >= point.y { candidates.append(rect.divided(atDistance: overlap.minY - rect.minY, from: .minYEdge).slice) }
            guard let best = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return nil }
            rect = best
        }
        guard rect.width >= minimumSize.width, rect.height >= minimumSize.height else { return nil }
        return rect
    }

    /// Space left beside a window snapped to the full height (or full width) of `visible` — what
    /// auto-layout offers to fill. nil for quarters, centred or full-screen windows.
    static func remainder(after frame: CGRect, in visible: CGRect, tolerance: CGFloat = 4) -> CGRect? {
        let spansHeight = abs(frame.minY - visible.minY) <= tolerance && abs(frame.maxY - visible.maxY) <= tolerance
        let spansWidth = abs(frame.minX - visible.minX) <= tolerance && abs(frame.maxX - visible.maxX) <= tolerance
        var candidates: [CGRect] = []
        if spansHeight && !spansWidth {
            candidates.append(CGRect(x: visible.minX, y: visible.minY, width: frame.minX - visible.minX, height: visible.height))
            candidates.append(CGRect(x: frame.maxX, y: visible.minY, width: visible.maxX - frame.maxX, height: visible.height))
        } else if spansWidth && !spansHeight {
            candidates.append(CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: frame.minY - visible.minY))
            candidates.append(CGRect(x: visible.minX, y: frame.maxY, width: visible.width, height: visible.maxY - frame.maxY))
        }
        return candidates
            .filter { $0.width >= minimumSize.width && $0.height >= minimumSize.height }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
