import SwiftUI

/// Circular usage gauge. Exposed to VoiceOver as one element with a value; level shown by
/// colour plus a text badge, never colour alone.
struct UsageRing: View {
    static let lineWidth: CGFloat = 6

    let fraction: Double // 0–1
    let label: String
    let symbol: String
    let detail: String
    var size: CGFloat = 64
    var action: (() -> Void)?

    private var clamped: Double { min(1, max(0, fraction)) }
    private var level: UsageLevel { UsageLevel(fraction: clamped) }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.tully)
                    .accessibilityHint("Shows details")
            } else {
                content
            }
        }
        .help(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((clamped * 100).rounded())) percent\(level.label.map { ", \($0)" } ?? ""). \(detail)")
    }

    private var content: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(Theme.color(for: level), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // ponytail: no easing on live updates; animating every 2 s sample doubled the popover's CPU
                VStack(spacing: 1) {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.2))
                        .foregroundStyle(.secondary)
                    Text("\(Int((clamped * 100).rounded()))%")
                        .font(.system(size: size * 0.2, weight: .semibold).monospacedDigit())
                }
            }
            .frame(width: size, height: size)

            HStack(spacing: 3) {
                Text(label).font(.caption.weight(.medium))
                if let symbol = level.symbol {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(Theme.color(for: level))
                }
            }
            Text(level.label ?? " ")
                .font(.caption2)
                .foregroundStyle(Theme.color(for: level))
        }
        .frame(maxWidth: .infinity)
    }
}
