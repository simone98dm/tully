import AppKit
import KumquatCore
import SwiftUI

/// Hosts SwiftUI sheets (tool parameters, editors, settings) in standalone windows for this menu bar app.
final class WindowPresenter {
    private var windows: [NSWindow] = []

    func present<V: View>(_ title: String, size: NSSize, @ViewBuilder content: (_ close: @escaping () -> Void) -> V) {
        let window = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        let close = { [weak self, weak window] in
            guard let window else { return }
            window.close()
            self?.windows.removeAll { $0 === window }
        }
        window.title = title
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content(close))
        window.center()
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Takes keyboard focus without activating the app: after a drop on the wheel Finder stays frontmost,
/// and macOS 14+ ignores activation requests from a menu bar app that wasn't clicked.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Generic parameter form built from `Tool.parameters(for:)`.
struct ToolForm: View {
    let tool: Tool
    let urls: [URL]
    let onRun: (ToolParams) -> Void
    let onCancel: () -> Void
    @State private var values: ToolParams = [:]
    private let parameters: [ToolParameter]

    init(tool: Tool, urls: [URL], onRun: @escaping (ToolParams) -> Void, onCancel: @escaping () -> Void) {
        self.tool = tool; self.urls = urls; self.onRun = onRun; self.onCancel = onCancel
        parameters = tool.parameters(for: urls)
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.defaultValue) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tool.name, systemImage: tool.symbol).font(.title3.weight(.semibold))
            Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Form {
                ForEach(parameters) { field($0) }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Run") { onRun(values) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private func binding(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { values[id] = $0 })
    }

    @ViewBuilder private func field(_ p: ToolParameter) -> some View {
        switch p.kind {
        case .slider(let min, let max, let step, let unit):
            let value = Binding<Double>(get: { Double(values[p.id] ?? "") ?? min }, set: { values[p.id] = String(Int($0)) })
            VStack(alignment: .leading) {
                HStack { Text(p.label); Spacer(); Text("\(values[p.id] ?? "")\(unit.hasPrefix("%") ? "" : " ")\(unit)").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: value, in: min...max, step: step).accessibilityLabel(p.label)
            }
        case .number(let unit):
            HStack {
                TextField(p.label, text: binding(p.id)).multilineTextAlignment(.trailing)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
            }
        case .text(let placeholder):
            TextField(p.label, text: binding(p.id), prompt: Text(placeholder))
        case .choice(let options):
            Picker(p.label, selection: binding(p.id)) { ForEach(options, id: \.self) { Text($0).tag($0) } }
        }
    }
}
