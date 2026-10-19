import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ConversionError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum ImageEngine {
    static let utis: [String: String] = [
        "jpg": "public.jpeg", "png": "public.png", "heic": "public.heic", "tiff": "public.tiff",
        "avif": "public.avif", "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif", "pdf": "com.adobe.pdf",
    ]
    static let lossy: Set<String> = ["jpg", "heic", "avif", "webp"]
    static let opaque: Set<String> = ["jpg", "bmp"]

    // MARK: Loading

    /// Loads the first frame with EXIF orientation applied.
    public static func load(_ url: URL) throws -> CGImage {
        let ext = canonicalExtension(of: url)
        if ext == "svg" { return try loadSVG(url) }
        if ext == "pdf" { return try PDFEngine.renderPage(url, index: 0, dpi: 300) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError("Can't read image \(url.lastPathComponent)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h, 1),
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return image
        }
        throw ConversionError("Can't decode image \(url.lastPathComponent)")
    }

    static func loadSVG(_ url: URL) throws -> CGImage {
        if let image = NSImage(contentsOf: url), image.size.width > 0 {
            let scale = max(1, 2048 / max(image.size.width, image.size.height))
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            var rect = NSRect(origin: .zero, size: size)
            if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) { return cg }
        }
        // ponytail: Quick Look fallback for SVGs NSImage can't parse.
        return try TempDir.with { dir in
            try Shell.run("/usr/bin/qlmanage", ["-t", "-s", "2048", "-o", dir.path, url.path])
            let png = dir.appendingPathComponent(url.lastPathComponent + ".png")
            return try load(png)
        }
    }

    public static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    public static func frameCount(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    // MARK: Writing

    /// Writes `image` as `ext`. `metadata` is copied when provided (orientation is reset, pixels are already upright).
    public static func write(_ image: CGImage, to url: URL, ext: String, quality: Double = 0.85,
                             metadata: [CFString: Any]? = nil) throws {
        if ext == "webp" { return try writeWebP(image, to: url, quality: quality) }
        guard let uti = utis[ext] else { throw ConversionError("Unsupported image output \(ext)") }
        let pixels = opaque.contains(ext) ? flatten(image) : image
        clearOutput(url)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else {
            throw ConversionError("Can't create \(ext.uppercased()) file")
        }
        var props = metadata ?? [:]
        props[kCGImagePropertyOrientation] = 1
        props.removeValue(forKey: kCGImagePropertyPixelWidth)
        props.removeValue(forKey: kCGImagePropertyPixelHeight)
        if lossy.contains(ext) { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, pixels, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConversionError("Failed writing \(ext.uppercased())") }
    }

    static func writeWebP(_ image: CGImage, to url: URL, quality: Double) throws {
        let cwebp = try Shell.require("cwebp")
        try TempDir.with { dir in
            let png = dir.appendingPathComponent("in.png")
            try write(image, to: png, ext: "png")
            try Shell.run(cwebp, ["-quiet", "-q", String(Int(quality * 100)), png.path, "-o", url.path])
        }
    }

    /// Composites onto white so formats without alpha don't turn transparent areas black.
    public static func flatten(_ image: CGImage) -> CGImage {
        guard let ctx = context(width: image.width, height: image.height) else { return image }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    public static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    public static func resized(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard let ctx = context(width: width, height: height) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    // MARK: Conversion

    public static func convert(_ input: URL, to ext: String, output: URL, quality: Double = 0.9) throws {
        let inExt = canonicalExtension(of: input)
        if inExt == "gif", ["mp4", "webm", "mov"].contains(ext) {
            return try MediaEngine.convert(input, to: ext, output: output)
        }
        if inExt == "gif", ext == "gif" { return try FileManager.default.copyItem(at: input, to: output) }
        let image = try load(input)
        let meta = (inExt == "svg" || inExt == "pdf") ? nil : properties(input)
        try write(image, to: output, ext: ext, quality: quality, metadata: meta)
    }
}
