import SwiftUI

struct MenuBarPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SystemMonitorService.self) private var monitor

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Preview") {
                StatusPreview(settings: settings, snapshot: monitor.snapshot)
            }

            Section {
                List {
                    ForEach(settings.statusOrder) { metric in
                        Toggle(isOn: Binding(get: { settings.isShown(metric) }, set: { settings.setShown(metric, $0) })) {
                            Label(metric.title, systemImage: metric.symbol)
                        }
                    }
                    .onMove(perform: settings.moveMetric)
                }
            } header: {
                Text("Stats")
            } footer: {
                Text("Drag to change the order.")
            }

            Section("Appearance") {
                Picker("Style", selection: $settings.statusStyle) {
                    ForEach(StatusStyle.allCases) { Text($0.title).tag($0) }
                }
                .accessibilityLabel("Style")
                Toggle(isOn: $settings.tintsHighUsage) {
                    Text("Highlight high usage")
                    Text("Shows a stat in orange above 65 % and red above 85 %.")
                }
                .accessibilityLabel("Highlight high usage")
            }
        }
        .formStyle(.grouped)
    }
}

/// Live rendering of the menu bar item with the current options, on both menu bar appearances.
private struct StatusPreview: View {
    let settings: AppSettings
    let snapshot: SystemSnapshot

    var body: some View {
        HStack(spacing: 12) {
            preview(.aqua, background: Color(white: 0.93))
            preview(.darkAqua, background: Color(white: 0.16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StatusBarFormatter.accessibilityLabel(
            for: StatusBarFormatter.segments(for: snapshot, metrics: settings.visibleMetrics)))
    }

    private func preview(_ name: NSAppearance.Name, background: Color) -> some View {
        let appearance = NSAppearance(named: name)!
        let image = StatusBarRenderer.image(
            segments: StatusBarFormatter.segments(for: snapshot, metrics: settings.visibleMetrics),
            style: settings.statusStyle, icon: NSImage(named: "MenuIcon"),
            tinted: settings.tintsHighUsage, appearance: appearance
        )
        return Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(name == .darkAqua ? Color.white : Color.black)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
    }
}
