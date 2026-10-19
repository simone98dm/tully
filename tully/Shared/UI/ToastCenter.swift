import SwiftUI

/// Short confirmation or error messages shown after an action ("Shortcut saved", "Couldn't quit …").
@Observable
final class ToastCenter {
    struct Toast: Equatable, Identifiable {
        enum Style { case success, info, error }
        let id = UUID()
        let message: String
        let style: Style

        var symbol: String {
            switch style {
            case .success: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    static let displayDuration: Duration = .seconds(2.5)

    private(set) var current: Toast?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .success) {
        let toast = Toast(message: message, style: style)
        current = toast
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled, self?.current == toast else { return }
            self?.current = nil
        }
    }

    func dismiss() { current = nil }
}

/// Overlay that renders the current toast at the bottom of its container.
struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = toasts.current {
                Label(toast.message, systemImage: toast.symbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(toast.style == .error ? AnyShapeStyle(Theme.destructive) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator))
                    .padding(.bottom, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { toasts.dismiss() }
                    .id(toast.id)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: toasts.current)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
