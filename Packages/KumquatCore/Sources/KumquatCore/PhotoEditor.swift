import CoreGraphics
import CoreImage
import CoreText
import AppKit

/// Non-destructive photo edit description, rendered by `PhotoEditor.render`.
/// All rects are normalized (0...1) with a top-left origin, relative to the original image.
public struct PhotoEdit: Codable, Equatable, Sendable {
    public struct Shape: Codable, Equatable, Sendable, Identifiable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case rectangle, ellipse, arrow, text, blackout, pixelate, blur }
        public var id = UUID()
        public var kind: Kind
        public var rect: CGRect
        public var color: String = "#FF3B30"
        public var lineWidth: Double = 0.006   // fraction of the image's longer side
        public var text: String = ""
        public init(kind: Kind, rect: CGRect, color: String = "#FF3B30", text: String = "") {
            self.kind = kind; self.rect = rect; self.color = color; self.text = text
        }
    }

    public var crop: CGRect?
    public var rotation = 0           // degrees clockwise: 0, 90, 180, 270
    public var flipHorizontal = false
    public var brightness = 0.0       // -1...1
    public var contrast = 1.0         // 0.25...2
    public var saturation = 1.0       // 0...2
    public var exposure = 0.0         // EV -2...2
    public var warmth = 0.0           // -1...1
    /// Arrow shapes keep a signed rect (origin = tail, origin + size = head).
    public var shapes: [Shape] = []

    public init() {}
    public var isIdentity: Bool { self == PhotoEdit() }
}

public enum PhotoEditor {
    public enum Mode: String, Sendable, CaseIterable { case crop, adjust, annotate, redact }

    static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    public static func render(_ source: CGImage, edit: PhotoEdit) throws -> CGImage {
        var image = CIImage(cgImage: source)
        let extent = image.extent

        // 1. Adjustments
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: edit.brightness * 0.5, kCIInputContrastKey: edit.contrast, kCIInputSaturationKey: edit.saturation,
        ])
        if edit.exposure != 0 { image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: edit.exposure]) }
        if edit.warmth != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 - edit.warmth * 3000, y: 0),
            ])
        }

        // 2. Region redactions (pixelate / blur) composited from filtered copies.
        for shape in edit.shapes where shape.kind == .pixelate || shape.kind == .blur {
            let rect = pixelRect(shape.rect, in: extent)
            let filtered = shape.kind == .pixelate
                ? image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(8, max(extent.width, extent.height) / 60),
                                                                  kCIInputCenterKey: CIVector(x: rect.minX, y: rect.minY)])
                : image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(extent.width, extent.height) / 50])
            image = filtered.cropped(to: rect).composited(over: image)
        }
        image = image.cropped(to: extent)
        guard var cg = ciContext.createCGImage(image, from: extent) else { throw ConversionError("Render failed") }

        // 3. Vector annotations + black boxes
        let vector = edit.shapes.filter { ![.pixelate, .blur].contains($0.kind) }
        if !vector.isEmpty { cg = try draw(vector, on: cg) }

        // 4. Crop, flip, rotate
        if let crop = edit.crop {
            let r = CGRect(x: crop.minX * CGFloat(cg.width), y: crop.minY * CGFloat(cg.height),
                           width: crop.width * CGFloat(cg.width), height: crop.height * CGFloat(cg.height)).integral
            guard let cropped = cg.cropping(to: r.intersection(CGRect(x: 0, y: 0, width: cg.width, height: cg.height))) else {
                throw ConversionError("Crop area is empty")
            }
            cg = cropped
        }
        if edit.flipHorizontal { cg = try transform(cg, rotation: 0, flip: true) }
        if edit.rotation % 360 != 0 { cg = try transform(cg, rotation: edit.rotation, flip: false) }
        return cg
    }

    /// Normalized top-left rect -> CoreImage pixel rect (bottom-left origin).
    static func pixelRect(_ r: CGRect, in extent: CGRect) -> CGRect {
        CGRect(x: r.minX * extent.width, y: (1 - r.maxY) * extent.height, width: r.width * extent.width, height: r.height * extent.height)
    }

    static func draw(_ shapes: [PhotoEdit.Shape], on image: CGImage) throws -> CGImage {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let ctx = ImageEngine.context(width: image.width, height: image.height) else { throw ConversionError("Render failed") }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        for shape in shapes {
            let rect = pixelRect(shape.rect, in: extent)
            let color = cgColor(hex: shape.color)
            let line = CGFloat(shape.lineWidth) * max(w, h)
            ctx.setStrokeColor(color); ctx.setFillColor(color); ctx.setLineWidth(line); ctx.setLineCap(.round)
            switch shape.kind {
            case .rectangle: ctx.stroke(rect)
            case .ellipse: ctx.strokeEllipse(in: rect)
            case .blackout: ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(rect)
            case .arrow:
                // Arrow runs from rect.origin to origin + size; size may be negative to point up/left.
                let r = shape.rect
                let start = CGPoint(x: r.origin.x * w, y: (1 - r.origin.y) * h)
                let end = CGPoint(x: (r.origin.x + r.size.width) * w, y: (1 - r.origin.y - r.size.height) * h)
                ctx.move(to: start); ctx.addLine(to: end); ctx.strokePath()
                let angle = atan2(end.y - start.y, end.x - start.x), head = line * 4
                for side in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8] {
                    ctx.move(to: end)
                    ctx.addLine(to: CGPoint(x: end.x + head * cos(angle + side), y: end.y + head * sin(angle + side)))
                }
                ctx.strokePath()
            case .text:
                let font = NSFont.boldSystemFont(ofSize: max(10, rect.height * 0.8))
                let text = NSAttributedString(string: shape.text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: color) ?? .red])
                let ctLine = CTLineCreateWithAttributedString(text)
                ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2)
                CTLineDraw(ctLine, ctx)
            case .pixelate, .blur: break
            }
        }
        guard let result = ctx.makeImage() else { throw ConversionError("Render failed") }
        return result
    }

    public static func transform(_ image: CGImage, rotation: Int, flip: Bool) throws -> CGImage {
        let quarter = ((rotation % 360) + 360) % 360 / 90
        let swap = quarter % 2 == 1
        let w = swap ? image.height : image.width, h = swap ? image.width : image.height
        guard let ctx = ImageEngine.context(width: w, height: h) else { throw ConversionError("Render failed") }
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: -CGFloat(quarter) * .pi / 2)   // clockwise
        if flip { ctx.scaleBy(x: -1, y: 1) }
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let result = ctx.makeImage() else { throw ConversionError("Render failed") }
        return result
    }

    public static func flipVertical(_ image: CGImage) throws -> CGImage {
        try transform(try transform(image, rotation: 180, flip: false), rotation: 0, flip: true)
    }

    public static func cgColor(hex: String) -> CGColor {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(clean, radix: 16) ?? 0xFF3B30
        return CGColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Renders the edit and writes it beside the original as "<name> edited.<ext>".
    public static func apply(_ edit: PhotoEdit, to input: URL, output: URL? = nil) throws -> URL {
        let inExt = canonicalExtension(of: input)
        let ext = ImageEngine.utis[inExt] != nil || inExt == "webp" ? inExt : "png"
        let output = output ?? OutputNamer.output(for: input, ext: ext, suffix: " edited")
        try ImageEngine.write(try render(try ImageEngine.load(input), edit: edit), to: output, ext: ext, quality: 0.92,
                              metadata: ImageEngine.properties(input))
        return output
    }
}
