import AppKit
import KumquatCore
import SwiftUI

/// Crop / adjust / annotate / redact editor. Produces a `PhotoEdit`; the core renders it at full resolution.
struct PhotoEditorView: View {
    let url: URL
    let onSave: (PhotoEdit) -> Void
    let onCancel: () -> Void

    @State private var mode: PhotoEditor.Mode
    @State private var edit = PhotoEdit()
    @State private var draft: CGRect?
    @State private var aspect: CGFloat? = nil
    @State private var shapeKind: PhotoEdit.Shape.Kind = .rectangle
    @State private var redactKind: PhotoEdit.Shape.Kind = .blackout
    @State private var color = Color.red
    @State private var text = "Text"
    @State private var preview: NSImage?
    @State private var loadError: String?
    private let source: CGImage?

    init(url: URL, mode: PhotoEditor.Mode, onSave: @escaping (PhotoEdit) -> Void, onCancel: @escaping () -> Void) {
        self.url = url; self.onSave = onSave; self.onCancel = onCancel
        _mode = State(initialValue: mode)
        // Work on a downscaled copy for interactive preview; normalized coordinates carry over to full size.
        let full = try? ImageEngine.load(url)
        source = full.map { image in
            let scale = min(1, 1400 / Double(max(image.width, image.height)))
            return ImageEngine.resized(image, width: Int(Double(image.width) * scale), height: Int(Double(image.height) * scale))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Mode", selection: $mode) {
                ForEach(PhotoEditor.Mode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420)

            canvas.frame(minWidth: 520, minHeight: 360)
            controls.frame(height: 110)

            HStack {
                Button("Reset") { edit = PhotoEdit(); render() }
                Button("Undo Shape") { if !edit.shapes.isEmpty { edit.shapes.removeLast(); render() } }.disabled(edit.shapes.isEmpty)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save Copy") { onSave(edit) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(edit.isIdentity)
            }
        }
        .padding(16)
        .onAppear(perform: render)
        .onChange(of: edit) { render() }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            if let preview, let source {
                let fit = fitted(CGSize(width: source.width, height: source.height), in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: preview).resizable().frame(width: fit.width, height: fit.height)
                    overlay(size: fit.size)
                }
                .frame(width: fit.width, height: fit.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { drag in
                    draft = normalized(drag.startLocation, drag.location, in: fit.size)
                }.onEnded { drag in
                    commit(normalized(drag.startLocation, drag.location, in: fit.size))
                    draft = nil
                })
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            } else {
                Text(loadError ?? "Can't open this image").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func overlay(size: CGSize) -> some View {
        if let crop = (mode == .crop ? draft : nil) ?? edit.crop {
            let r = denormalized(crop, in: size)
            Path { p in p.addRect(CGRect(origin: .zero, size: size)); p.addRect(r) }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            Rectangle().stroke(Color.white, lineWidth: 1.5).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        }
        if let draft, mode != .crop {
            let r = denormalized(draft.standardized, in: size)
            Rectangle().stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4])).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        switch mode {
        case .crop:
            HStack(spacing: 16) {
                Picker("Aspect", selection: $aspect) {
                    Text("Free").tag(CGFloat?.none)
                    Text("1:1").tag(CGFloat?(1)); Text("4:3").tag(CGFloat?(4.0 / 3)); Text("16:9").tag(CGFloat?(16.0 / 9))
                }.frame(width: 160)
                Button { edit.rotation = (edit.rotation + 270) % 360 } label: { Label("Rotate Left", systemImage: "rotate.left") }
                Button { edit.rotation = (edit.rotation + 90) % 360 } label: { Label("Rotate Right", systemImage: "rotate.right") }
                Toggle("Flip", isOn: $edit.flipHorizontal)
                Button("Clear Crop") { edit.crop = nil }.disabled(edit.crop == nil)
            }
            .overlay(alignment: .bottom) { Text("Drag on the image to choose the crop. Rotation \(edit.rotation)°").font(.caption).foregroundStyle(.secondary).offset(y: 30) }
        case .adjust:
            Grid(alignment: .leading, verticalSpacing: 4) {
                slider("Brightness", $edit.brightness, -1...1)
                slider("Contrast", $edit.contrast, 0.25...2)
                slider("Saturation", $edit.saturation, 0...2)
                slider("Exposure", $edit.exposure, -2...2)
                slider("Warmth", $edit.warmth, -1...1)
            }
        case .annotate:
            HStack(spacing: 16) {
                Picker("Shape", selection: $shapeKind) {
                    ForEach([PhotoEdit.Shape.Kind.rectangle, .ellipse, .arrow, .text], id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(width: 180)
                ColorPicker("Color", selection: $color)
                if shapeKind == .text { TextField("Text", text: $text).frame(width: 160) }
            }
            .overlay(alignment: .bottom) { Text("Drag on the image to place the shape").font(.caption).foregroundStyle(.secondary).offset(y: 30) }
        case .redact:
            HStack {
                Picker("Style", selection: $redactKind) {
                    Text("Black Box").tag(PhotoEdit.Shape.Kind.blackout)
                    Text("Pixelate").tag(PhotoEdit.Shape.Kind.pixelate)
                    Text("Blur").tag(PhotoEdit.Shape.Kind.blur)
                }.pickerStyle(.segmented).frame(width: 300)
            }
            .overlay(alignment: .bottom) { Text("Drag over what you want hidden").font(.caption).foregroundStyle(.secondary).offset(y: 30) }
        }
    }

    private func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        GridRow {
            Text(label).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range).frame(width: 300).accessibilityLabel(label)
        }
    }

    // MARK: Geometry + actions

    private func fitted(_ image: CGSize, in box: CGSize) -> CGRect {
        let scale = min(box.width / image.width, box.height / image.height)
        return CGRect(x: 0, y: 0, width: image.width * scale, height: image.height * scale)
    }

    private func normalized(_ a: CGPoint, _ b: CGPoint, in size: CGSize) -> CGRect {
        var rect = CGRect(x: min(a.x, b.x) / size.width, y: min(a.y, b.y) / size.height,
                          width: abs(a.x - b.x) / size.width, height: abs(a.y - b.y) / size.height)
        if mode == .crop, let aspect {
            // Keep pixel aspect: height in normalized units depends on the image's own ratio.
            rect.size.height = rect.width * size.width / aspect / size.height
        }
        if mode == .annotate, shapeKind == .arrow {
            // Signed rect: tail at the drag start, head at the drag end.
            return CGRect(x: a.x / size.width, y: a.y / size.height, width: (b.x - a.x) / size.width, height: (b.y - a.y) / size.height)
        }
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func denormalized(_ r: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    private func commit(_ rect: CGRect) {
        guard abs(rect.width) > 0.005 || abs(rect.height) > 0.005 else { return }
        switch mode {
        case .crop: edit.crop = rect
        case .adjust: break
        case .annotate:
            edit.shapes.append(PhotoEdit.Shape(kind: shapeKind, rect: rect, color: hex(color), text: text))
        case .redact:
            edit.shapes.append(PhotoEdit.Shape(kind: redactKind, rect: rect))
        }
    }

    private func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .red
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    /// Preview shows adjustments and shapes in original framing; crop/rotation apply on save.
    private func render() {
        guard let source else { loadError = "Can't open \(url.lastPathComponent)"; return }
        var previewEdit = edit
        previewEdit.crop = nil
        previewEdit.rotation = 0
        previewEdit.flipHorizontal = false
        do {
            let image = try PhotoEditor.render(source, edit: previewEdit)
            preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            loadError = error.localizedDescription
        }
    }
}
