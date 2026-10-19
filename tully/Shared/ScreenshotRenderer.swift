import AppKit
import KumquatCore
import SwiftUI

/// `tully --render-screenshots <dir>` writes PNGs of overlays and panels that are hard to capture
/// live (they appear mid-drag or over other apps), using sample data, then quits.
enum ScreenshotRenderer {
    static func run(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let samples = try SampleFiles(in: FileManager.default.temporaryDirectory.appendingPathComponent("tully-screenshot-samples"))

        // File Converter wheels (Convert for an image, Tools for a PDF, Actions)
        for (kind, file, highlight, name) in [(WheelKind.convert, samples.png, 1, "wheel-convert"),
                                              (.tools, samples.pdf, 0, "wheel-tools"),
                                              (.actions, samples.png, 4, "wheel-actions"),
                                              (.actions, samples.folder, 6, "wheel-actions-folder"),
                                              (.actions, samples.code, 6, "wheel-actions-code")] {
            let view = WheelView(frame: NSRect(x: 0, y: 0, width: WheelPanel.size, height: WheelPanel.size))
            view.configure(kind: kind, items: DragMonitor.items(for: kind, urls: [file]), fileCount: 1)
            view.highlighted = highlight
            try snapshot(view, background: .windowBackgroundColor, to: dir.appendingPathComponent("\(name).png"))
        }

        try menuBarStyles(to: dir.appendingPathComponent("menubar-styles.png"))

        let hud = HUDModel()
        hud.state = .done("Converted to WebP", [samples.png])
        let swiftUI: [(String, AnyView, NSSize)] = [
            ("converter-onboarding", AnyView(OnboardingView {}), NSSize(width: 460, height: 420)),
            ("converter-tool-form", AnyView(ToolForm(tool: Tools.tool("compress")!, urls: [samples.png], onRun: { _ in }, onCancel: {})),
             NSSize(width: 440, height: 300)),
            ("converter-photo-editor", AnyView(PhotoEditorView(url: samples.png, mode: .annotate, onSave: { _ in }, onCancel: {})),
             NSSize(width: 760, height: 640)),
            ("converter-pdf-pages", AnyView(PDFPagesView(url: samples.pdf, onSave: { _ in }, onCancel: {})), NSSize(width: 520, height: 560)),
            ("converter-hud", AnyView(HUDView(model: hud)), NSSize(width: 280, height: 64)),
        ]
        for (name, view, size) in swiftUI {
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: size)
            try snapshot(host, background: .windowBackgroundColor, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// Glass and materials only render on screen, so these scenes open in a real window
    /// (`--show-scene=<name>`) and `scripts/screenshots.sh` captures it by window id.
    static let scenes: [String: () -> AnyView] = [
        "window-ring": { AnyView(RingScene()) },
        "auto-layout": { AnyView(AutoLayoutScene()) },
        "keyboard-cleaning": { AnyView(KeyboardCleaningScene()) },
    ]

    static func showScene(_ name: String) -> NSWindow? {
        guard let make = scenes[name] else { return nil }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = name
        window.contentView = NSHostingView(rootView: make())
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }

    /// Every menu bar style on light and dark bars, from the real renderer.
    static func menuBarStyles(to url: URL) throws {
        var snap = DemoData.snapshot(step: 9)
        snap.cpuPercent = 72 // shows the high-usage tint
        let segments = StatusBarFormatter.segments(for: snap, metrics: [.cpu, .ram, .disk, .net])
        let rows = StatusStyle.allCases.flatMap { style in [(style, false), (style, true)] }
        let rowHeight: CGFloat = 34, width: CGFloat = 520
        let size = NSSize(width: width, height: rowHeight * CGFloat(rows.count))
        let image = NSImage(size: size, flipped: true) { _ in
            for (index, (style, dark)) in rows.enumerated() {
                let rect = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: width, height: rowHeight)
                (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.92, alpha: 1)).setFill()
                rect.fill()
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                let bar = StatusBarRenderer.image(segments: segments, style: style, icon: NSImage(named: "MenuIcon"),
                                                  tinted: true, appearance: appearance)
                let drawn = bar.isTemplate ? tinted(bar, dark ? .white : .black) : bar
                drawn.draw(in: NSRect(x: width - bar.size.width - 14, y: rect.minY + (rowHeight - bar.size.height) / 2,
                                      width: bar.size.width, height: bar.size.height))
                (style.title as NSString).draw(at: NSPoint(x: 12, y: rect.minY + 10), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: dark ? NSColor.lightGray : NSColor.darkGray])
            }
            return true
        }
        let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        scaled.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try scaled.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    static func snapshot(_ view: NSView, background: NSColor, to url: URL) throws {
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = background
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4)) // let SwiftUI settle
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// A tiny image and PDF to feed the converter screens.
private struct SampleFiles {
    let png: URL
    let pdf: URL
    let folder: URL
    let code: URL

    init(in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        png = dir.appendingPathComponent("Sunset.png")
        pdf = dir.appendingPathComponent("Report.pdf")
        folder = dir.appendingPathComponent("Project")
        code = dir.appendingPathComponent("main.swift")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("print(\"hi\")\n".utf8).write(to: code)
        let ctx = ImageEngine.context(width: 600, height: 400)!
        ctx.setFillColor(CGColor(red: 0.98, green: 0.62, blue: 0.25, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        ctx.setFillColor(CGColor(red: 0.98, green: 0.85, blue: 0.4, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 220, y: 120, width: 160, height: 160))
        ctx.setFillColor(CGColor(red: 0.3, green: 0.2, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 110))
        let image = ctx.makeImage()!
        try ImageEngine.write(image, to: png, ext: "png")
        try PDFEngine.pdf(fromImages: [image, image, image], to: pdf)
    }
}

/// Mock desktop with two windows, used behind overlay screenshots.
private struct DemoDesktop<Overlay: View>: View {
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.35, blue: 0.6), Color(red: 0.45, green: 0.3, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            overlay()
        }
        .frame(width: 900, height: 560)
        .environment(\.colorScheme, .dark)
    }
}

private struct MockWindow: View {
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 10, height: 10) }
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            .padding(8)
            .background(Color(white: 0.22))
            Color(white: 0.16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 12)
    }
}

private struct RingScene: View {
    @State private var ring: WindowRingService = {
        let defaults = UserDefaults(suiteName: "tully.screenshots")!
        return WindowRingService(defaults: defaults, eventTap: nil, windowManager: WindowManagerService(defaults: defaults))
    }()

    var body: some View {
        DemoDesktop {
            MockWindow(title: "Notes").frame(width: 420, height: 300).position(x: 560, y: 300)
            RingPreviewView().frame(width: 450, height: 560).position(x: 225, y: 280)
            RingView().environment(ring).position(x: 560, y: 300)
                .onAppear { ring.highlightForScreenshot(.leftHalf) }
        }
    }
}

private struct AutoLayoutScene: View {
    private let controller: AutoLayoutController = {
        let controller = AutoLayoutController(eventTap: nil)
        let icon = { (path: String) in NSWorkspace.shared.icon(forFile: path) }
        controller.loadCandidatesForScreenshot([
            WindowInfo(id: 1, appName: "Safari", windowTitle: "Apple Developer", pid: 1, appIcon: icon("/Applications/Safari.app")),
            WindowInfo(id: 2, appName: "Notes", windowTitle: "Ideas", pid: 2, appIcon: icon("/System/Applications/Notes.app")),
            WindowInfo(id: 3, appName: "Music", windowTitle: "", pid: 3, appIcon: icon("/System/Applications/Music.app")),
        ])
        return controller
    }()

    var body: some View {
        DemoDesktop {
            MockWindow(title: "Xcode — tully").frame(width: 440, height: 540).position(x: 230, y: 280)
            AutoLayoutView().environment(controller).frame(width: 430, height: 520).position(x: 670, y: 280)
        }
    }
}

private struct KeyboardCleaningScene: View {
    private let service: KeyboardCleaningService = {
        let service = KeyboardCleaningService(defaults: UserDefaults(suiteName: "tully.screenshots")!, isTrusted: { true },
                                              startBlocking: { true }, stopBlocking: {}, showsOverlay: false, tick: .seconds(3600))
        service.setEnabled(true)
        return service
    }()

    var body: some View {
        DemoDesktop {
            MockWindow(title: "Pages").frame(width: 600, height: 400)
            KeyboardCleaningOverlayView().environment(service)
        }
    }
}
