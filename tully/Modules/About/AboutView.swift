import AppKit
import SwiftUI

/// About window: icon, version, what tully does, links and credits.
struct AboutView: View {
    static let size = CGSize(width: 420, height: 530)

    @Environment(PopoverState.self) private var popover
    @State private var copied = false

    private static let features: [(symbol: String, title: String)] = [
        ("gauge.with.dots.needle.67percent", "System stats in the menu bar and a full System Monitor"),
        ("circle.dashed.inset.filled", "Window zones, the Window Ring (⌃⌥) and tiling suggestions"),
        ("rectangle.on.rectangle.angled", "A window switcher for every window, even of the same app"),
        ("arrow.triangle.2.circlepath", "File Converter: convert, edit and share files mid-drag"),
        ("trash", "Disk Clean, Stay Awake and Keyboard Cleaning"),
    ]

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var version: String { info["CFBundleShortVersionString"] as? String ?? "?" }
    private var build: String { info["CFBundleVersion"] as? String ?? "?" }
    private var versionLine: String { "Version \(version) (\(build))" }

    var body: some View {
        VStack(spacing: 18) {
            header
            Divider()
            featureList
            Divider()
            links
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: AppIcon.image)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("tully").font(.largeTitle.weight(.bold))
            Text("Your Mac, at a glance and in order.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("tully \(versionLine)", forType: .string)
                copied = true
            } label: {
                Label(copied ? "Copied" : versionLine, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.monospacedDigit())
            }
            .buttonStyle(.tully)
            .foregroundStyle(.secondary)
            .help("Copy version")
            .accessibilityLabel(versionLine)
            .accessibilityHint("Copies the version to the clipboard")
        }
        .accessibilityElement(children: .contain)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.features, id: \.title) { feature in
                Label {
                    Text(feature.title).font(.callout).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: feature.symbol)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var links: some View {
        HStack(spacing: 10) {
            link("GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: "https://github.com/simone98dm/tully")
            link("Report a Problem", symbol: "exclamationmark.bubble", url: "https://github.com/simone98dm/tully/issues")
            Button { popover.open(.settings(nil)) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .pointerStyle(.link)
        }
        .controlSize(.small)
    }

    private func link(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.bordered)
        .pointerStyle(.link)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("No telemetry. Everything runs on your Mac.")
            Text("Inspired by different apps tools. © 2026 simone98dm")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

/// The icon shipped in this bundle. `NSApp.applicationIconImage` goes through the system icon cache,
/// which can return another installed copy's icon (same bundle id, e.g. an older tully in /Applications).
enum AppIcon {
    static let image: NSImage = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
}
