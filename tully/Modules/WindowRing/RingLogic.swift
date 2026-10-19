import CoreGraphics

/// Pure mapping from cursor movement to window zones (clean-room, no Loop code).
nonisolated enum RingLogic {
    /// 8 directions, counter-clockwise from 3 o'clock (y up).
    enum Direction: Int, CaseIterable, Sendable {
        case east, northEast, north, northWest, west, southWest, south, southEast

        var zone: WindowZone {
            switch self {
            case .east: .rightHalf
            case .northEast: .topRight
            case .north: .topHalf
            case .northWest: .topLeft
            case .west: .leftHalf
            case .southWest: .bottomLeft
            case .south: .bottomHalf
            case .southEast: .bottomRight
            }
        }

        /// Pushing further out picks a bigger or narrower variant.
        var outerZone: WindowZone {
            switch self {
            case .east: .rightThird
            case .west: .leftThird
            case .north: .fullscreen
            case .south: .centerThird
            default: zone
            }
        }

        /// Center angle in radians (y up).
        var angle: CGFloat { CGFloat(rawValue) * .pi / 4 }
    }

    /// Direction for a cursor offset from the ring center (y up), or nil inside the hub (cancel).
    static func direction(for offset: CGVector, hubRadius: CGFloat) -> Direction? {
        guard hypot(offset.dx, offset.dy) >= hubRadius else { return nil }
        var angle = atan2(offset.dy, offset.dx)
        if angle < 0 { angle += 2 * .pi }
        return Direction(rawValue: Int((angle / (.pi / 4)).rounded()) % 8)
    }

    /// Zone for a cursor offset: hub = nil, ring = halves/quarters, beyond `outerRadius` = outer variant.
    static func zone(for offset: CGVector, hubRadius: CGFloat, outerRadius: CGFloat) -> WindowZone? {
        guard let direction = direction(for: offset, hubRadius: hubRadius) else { return nil }
        return hypot(offset.dx, offset.dy) > outerRadius ? direction.outerZone : direction.zone
    }
}
