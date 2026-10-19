import SwiftUI

/// The radial menu: 8 wedges (halves and quarters) around a cancel hub.
struct RingView: View {
    @Environment(WindowRingService.self) private var ring

    var body: some View {
        let diameter = ring.ringSize.diameter
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: diameter, height: diameter)
            ForEach(RingLogic.Direction.allCases, id: \.rawValue) { direction in
                wedge(direction, diameter: diameter)
            }
            Circle()
                .fill(.regularMaterial)
                .frame(width: ring.hubRadius * 2, height: ring.hubRadius * 2)
            VStack(spacing: 2) {
                Image(systemName: ring.highlightedZone == nil ? "xmark" : ring.highlightedZone!.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Text(ring.highlightedZone?.displayName ?? "Cancel")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: ring.hubRadius * 2 - 6)
            .foregroundStyle(ring.highlightedZone == nil ? .secondary : .primary)
        }
        .frame(width: diameter + 60, height: diameter + 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Window ring")
        .accessibilityValue(ring.highlightedZone?.displayName ?? "Cancel")
    }

    private func wedge(_ direction: RingLogic.Direction, diameter: CGFloat) -> some View {
        let isOn = ring.highlightedZone == direction.zone || ring.highlightedZone == direction.outerZone
        let radius = (diameter / 2 + ring.hubRadius) / 2
        return ZStack {
            WedgeShape(angle: direction.angle, sweep: .pi / 4, inner: ring.hubRadius + 3, outer: diameter / 2 - 2)
                .fill(isOn ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.06))
            Image(systemName: direction.zone.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isOn ? .white : .secondary)
                .offset(x: cos(direction.angle) * radius, y: -sin(direction.angle) * radius)
        }
    }
}

/// Annular sector centered on `angle` (radians, counter-clockwise, y up).
private struct WedgeShape: Shape {
    let angle: CGFloat
    let sweep: CGFloat
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI's y grows downward, so negate angles
        let start = Angle(radians: -(angle + sweep / 2) + 0.02)
        let end = Angle(radians: -(angle - sweep / 2) - 0.02)
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Translucent outline of where the window will land.
struct RingPreviewView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.accentColor.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 3))
            .padding(6)
            .accessibilityHidden(true)
    }
}
