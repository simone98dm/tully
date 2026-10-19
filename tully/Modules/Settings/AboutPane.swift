import SwiftUI

struct AboutPane: View {
    @Environment(PopoverState.self) private var popover
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Button { popover.open(.about) } label: { Label("About tully…", systemImage: "info.circle") }
                    .pointerStyle(.link)
                Link(destination: URL(string: "https://github.com/simone98dm/tully")!) {
                    Label("Project on GitHub", systemImage: "arrow.up.forward.square")
                }
                .pointerStyle(.link)
                Link(destination: URL(string: "https://github.com/simone98dm/tully/issues")!) {
                    Label("Report a problem", systemImage: "exclamationmark.bubble")
                }
                .pointerStyle(.link)
            }
            Section("Keyboard") {
                LabeledContent("Open Settings", value: "⌘,")
                LabeledContent("Switch popover tabs", value: "⌘1 … ⌘5  or  ← →")
                LabeledContent("Cancel a shortcut recording", value: "Esc")
            }
        }
        .formStyle(.grouped)
    }
}
