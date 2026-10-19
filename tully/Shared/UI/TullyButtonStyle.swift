import SwiftUI

/// Pointer cursor, hover highlight, pressed feedback and a disabled look for every clickable element.
struct TullyButtonStyle: ButtonStyle {
    enum Kind { case plain, row, tab, icon }

    var kind: Kind = .plain
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration, kind: kind, isSelected: isSelected)
    }
}

private struct StyledButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TullyButtonStyle.Kind
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .padding(padding)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 && isEnabled }
            .pointerStyle(isEnabled ? .link : nil)
    }

    private var padding: EdgeInsets {
        switch kind {
        case .plain: EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
        case .row: Theme.rowPadding
        case .tab: EdgeInsets(top: 6, leading: 2, bottom: 6, trailing: 2)
        case .icon: EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
        }
    }

    private var backgroundOpacity: Double {
        if configuration.isPressed { return 0.14 }
        if isHovered { return 0.08 }
        return isSelected ? 0.06 : 0
    }
}

extension ButtonStyle where Self == TullyButtonStyle {
    static var tully: TullyButtonStyle { TullyButtonStyle() }
    static var tullyRow: TullyButtonStyle { TullyButtonStyle(kind: .row) }
    static var tullyIcon: TullyButtonStyle { TullyButtonStyle(kind: .icon) }
}
