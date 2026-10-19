import SwiftUI

/// Usage levels shared by rings, bars and the menu bar tint. Never shown by colour alone:
/// `label` and `symbol` give a text/icon alternative.
nonisolated enum UsageLevel: Equatable, Sendable {
    case normal, elevated, critical

    static let elevatedThreshold = 0.65
    static let criticalThreshold = 0.85

    init(fraction: Double) {
        switch fraction {
        case Self.criticalThreshold...: self = .critical
        case Self.elevatedThreshold...: self = .elevated
        default: self = .normal
        }
    }

    var label: String? {
        switch self {
        case .normal: nil
        case .elevated: "High"
        case .critical: "Critical"
        }
    }

    var symbol: String? {
        switch self {
        case .normal: nil
        case .elevated: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

enum Theme {
    /// Semantic colours. System colours adapt to light/dark and Increase Contrast.
    static func color(for level: UsageLevel) -> Color {
        switch level {
        case .normal: .accentColor
        case .elevated: .orange
        case .critical: .red
        }
    }

    static let download = Color.blue
    static let upload = Color.orange
    static let warning = Color.orange
    static let destructive = Color.red
    static let cornerRadius: CGFloat = 8
    static let rowPadding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
}
