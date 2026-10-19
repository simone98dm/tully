import CoreGraphics

nonisolated enum WindowZone: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case fullscreen
    case topLeft, topRight, bottomLeft, bottomRight

    var displayName: String {
        switch self {
        case .leftHalf:       "Left Half"
        case .rightHalf:      "Right Half"
        case .topHalf:        "Top Half"
        case .bottomHalf:     "Bottom Half"
        case .leftThird:      "Left ⅓"
        case .centerThird:    "Center ⅓"
        case .rightThird:     "Right ⅓"
        case .leftTwoThirds:  "Left ⅔"
        case .rightTwoThirds: "Right ⅔"
        case .fullscreen:     "Fullscreen"
        case .topLeft:        "Top-Left"
        case .topRight:       "Top-Right"
        case .bottomLeft:     "Bottom-Left"
        case .bottomRight:    "Bottom-Right"
        }
    }

    /// Target frame inside a screen's visible frame, in AppKit (bottom-left origin) coordinates.
    func frame(in f: CGRect) -> CGRect {
        let w = f.width, h = f.height
        switch self {
        case .leftHalf:       return CGRect(x: f.minX,           y: f.minY, width: w / 2,     height: h)
        case .rightHalf:      return CGRect(x: f.midX,           y: f.minY, width: w / 2,     height: h)
        case .topHalf:        return CGRect(x: f.minX,           y: f.midY, width: w,         height: h / 2)
        case .bottomHalf:     return CGRect(x: f.minX,           y: f.minY, width: w,         height: h / 2)
        case .leftThird:      return CGRect(x: f.minX,           y: f.minY, width: w / 3,     height: h)
        case .centerThird:    return CGRect(x: f.minX + w / 3,   y: f.minY, width: w / 3,     height: h)
        case .rightThird:     return CGRect(x: f.minX + 2 * w / 3, y: f.minY, width: w / 3,   height: h)
        case .leftTwoThirds:  return CGRect(x: f.minX,           y: f.minY, width: 2 * w / 3, height: h)
        case .rightTwoThirds: return CGRect(x: f.minX + w / 3,   y: f.minY, width: 2 * w / 3, height: h)
        case .fullscreen:     return f
        case .topLeft:        return CGRect(x: f.minX,           y: f.midY, width: w / 2,     height: h / 2)
        case .topRight:       return CGRect(x: f.midX,           y: f.midY, width: w / 2,     height: h / 2)
        case .bottomLeft:     return CGRect(x: f.minX,           y: f.minY, width: w / 2,     height: h / 2)
        case .bottomRight:    return CGRect(x: f.midX,           y: f.minY, width: w / 2,     height: h / 2)
        }
    }

    /// SF Symbol that sketches the zone, for menus and the ring.
    var symbol: String {
        switch self {
        case .leftHalf:       "rectangle.lefthalf.filled"
        case .rightHalf:      "rectangle.righthalf.filled"
        case .topHalf:        "rectangle.tophalf.filled"
        case .bottomHalf:     "rectangle.bottomhalf.filled"
        case .leftThird, .leftTwoThirds:   "rectangle.leadingthird.inset.filled"
        case .centerThird:    "rectangle.center.inset.filled"
        case .rightThird, .rightTwoThirds: "rectangle.trailingthird.inset.filled"
        case .fullscreen:     "rectangle.inset.filled"
        case .topLeft:        "rectangle.inset.topleft.filled"
        case .topRight:       "rectangle.inset.topright.filled"
        case .bottomLeft:     "rectangle.inset.bottomleft.filled"
        case .bottomRight:    "rectangle.inset.bottomright.filled"
        }
    }
}
