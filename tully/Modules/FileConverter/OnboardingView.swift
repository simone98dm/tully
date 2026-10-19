import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text("File Converter").font(.title2.weight(.bold))
                    Text("Convert, edit and share files mid-drag. Everything stays on your Mac.").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            step("1", "Drag any file", "Start dragging a file from Finder, the desktop or any app.")
            step("2", "Tap ⇧ Shift", "A wheel of formats appears under your cursor.")
            step("3", "Drop on a format", "The converted copy appears next to the original.")
            Divider()
            Text("Tap ⌘ Command mid-drag for tools (compress, trim, crop, metadata…) and ⌃ Control for actions (AirDrop, Float, Copy, Move…). Drop in the center to cancel. Change keys or turn the File Converter off in tully Settings.")
                .font(.callout).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Get Started", action: onDone).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).font(.headline).frame(width: 26, height: 26).background(Circle().fill(Color.accentColor.opacity(0.2)))
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary) }
        }
    }
}
