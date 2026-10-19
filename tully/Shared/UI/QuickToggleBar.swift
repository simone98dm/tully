import SwiftUI

/// One Menu-style quick toggles at the bottom of the popover.
struct QuickToggleBar: View {
    @Environment(PreventSleepService.self) private var preventSleep
    @Environment(KeyboardCleaningService.self) private var keyboardCleaning
    @Environment(ToastCenter.self) private var toasts
    @Environment(FileConverterController.self) private var converter

    var body: some View {
        HStack(spacing: 8) {
            QuickToggle(title: "Stay Awake", symbol: "cup.and.saucer", isOn: preventSleep.isEnabled,
                        detail: preventSleep.endsAt.map { "until \($0.formatted(date: .omitted, time: .shortened))" }) {
                preventSleep.setEnabled(!preventSleep.isEnabled)
                toasts.show(preventSleep.isEnabled ? "Your Mac will stay awake" : "Sleep allowed again", style: .info)
            }
            QuickToggle(title: "Keyboard Clean", symbol: "keyboard", isOn: keyboardCleaning.isEnabled, detail: nil) {
                if !keyboardCleaning.setEnabled(!keyboardCleaning.isEnabled) {
                    toasts.show("Keyboard Cleaning needs Accessibility access", style: .error)
                }
            }
            QuickToggle(title: "Converter", symbol: "arrow.triangle.2.circlepath.circle", isOn: converter.settings.isEnabled, detail: nil) {
                converter.setEnabled(!converter.settings.isEnabled)
                toasts.show(converter.settings.isEnabled ? "File Converter on" : "File Converter off", style: .info)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct QuickToggle: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: isOn ? symbol + ".fill" : symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
                Text(detail ?? (isOn ? "On" : "Off"))
                    .font(.caption2)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? Color.accentColor : .primary)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(isOn ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
        }
        .buttonStyle(.tully)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
