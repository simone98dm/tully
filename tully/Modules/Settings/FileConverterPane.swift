import AppKit
import KumquatCore
import SwiftUI

struct FileConverterPane: View {
    @Environment(FileConverterController.self) private var converter

    var body: some View {
        @Bindable var settings = converter.settings
        Form {
            Section {
                Toggle(isOn: Binding(get: { settings.isEnabled }, set: { converter.setEnabled($0) })) {
                    Text("Enable File Converter")
                    Text("Start dragging a file and tap a modifier key to open a wheel of conversions, tools or actions.")
                }
                .accessibilityLabel("Enable File Converter")
            }
            Group {
                Section {
                    modifierPicker("Convert wheel", \.convert, settings: settings)
                    modifierPicker("Tools wheel", \.tools, settings: settings)
                    modifierPicker("Actions wheel", \.actions, settings: settings)
                    if settings.hasConflict {
                        Label("Two wheels share the same keys; the first one wins.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warning)
                    }
                    Button("Restore Default Keys") { settings.binding = .default }
                        .pointerStyle(.link)
                } header: {
                    Text("Wheels")
                } footer: {
                    Text("While a wheel is open: arrows move, Return picks (or opens the full list), Esc closes. The wheels only react while you're dragging files, so they never clash with the Window Ring.")
                }

                Section("Save results") {
                    Picker("Location", selection: $settings.useCustomFolder) {
                        Text("Next to the original").tag(false)
                        Text("In a folder").tag(true)
                    }
                    .accessibilityLabel("Location")
                    if settings.useCustomFolder {
                        LabeledContent("Folder") {
                            HStack {
                                Text(settings.customFolder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                                Button("Choose…") { chooseFolder(settings) }.pointerStyle(.link)
                            }
                        }
                    }
                    Toggle("Reveal results in Finder", isOn: $settings.revealOutput)
                    .accessibilityLabel("Reveal results in Finder")
                }

                Section {
                    DependencyRow(name: "ffmpeg", purpose: "video and audio", install: "brew install ffmpeg")
                    DependencyRow(name: "cwebp", purpose: "WebP output", install: "brew install webp")
                } header: {
                    Text("Helpers")
                } footer: {
                    Text("Everything runs locally; files never leave your Mac. Pages, Keynote and Numbers are used for iWork formats when installed.")
                }

                Section {
                    Button("Clear Recent Results") { settings.clearRecents() }
                        .disabled(settings.recents.isEmpty)
                    Button("How File Converter Works") { converter.showOnboarding() }
                }
                .pointerStyle(.link)
            }
            .disabled(!settings.isEnabled)
        }
        .formStyle(.grouped)
    }

    private func modifierPicker(_ label: String, _ keyPath: WritableKeyPath<ModifierBinding, UInt>,
                                settings: ConverterSettings) -> some View {
        let options: [(String, UInt)] = ModifierBinding.choices.map { ($0.0, $0.1.rawValue) }
            + [("⌥⇧ Option + Shift", NSEvent.ModifierFlags([.option, .shift]).rawValue)]
        return Picker(label, selection: Binding(get: { settings.binding[keyPath: keyPath] },
                                                set: { settings.binding[keyPath: keyPath] = $0 })) {
            ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
        }
        .accessibilityLabel(label)
    }

    private func chooseFolder(_ settings: ConverterSettings) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { settings.customFolder = url.path }
    }
}
