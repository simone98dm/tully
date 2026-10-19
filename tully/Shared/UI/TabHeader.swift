import SwiftUI

/// Icon + title (+ optional subtitle and trailing accessory) at the top of each popover tab.
struct TabHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // title + subtitle read as one header; the accessory stays its own control
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

extension TabHeader where Accessory == EmptyView {
    init(title: String, symbol: String, subtitle: String? = nil) {
        self.init(title: title, symbol: symbol, subtitle: subtitle) { EmptyView() }
    }
}

/// Icon + one line + optional action, for empty / loading / error states.
struct EmptyStateView: View {
    let symbol: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .pointerStyle(.link)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
