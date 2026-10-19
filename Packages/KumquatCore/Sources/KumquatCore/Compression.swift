import Foundation
import ImageIO
import PDFKit

/// Size-targeted compression for images, video, audio and PDF.
public enum Compression {
    static let lossless: Set<String> = ["wav", "flac", "aiff"]

    public static func fileSize(_ url: URL) -> Int {
        // Not URL.resourceValues: those are cached per URL instance and go stale across rewrites.
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// Compresses to at most `targetBytes` when achievable; otherwise produces the smallest reasonable result.
    /// Throws (leaving nothing behind) when the result wouldn't be smaller than the original.
    @discardableResult
    public static func compress(_ input: URL, targetBytes: Int, output: URL? = nil) throws -> URL {
        guard targetBytes > 0 else { throw ConversionError("Target size must be greater than zero") }
        let result = try compressAnyway(input, targetBytes: targetBytes, output: output)
        if fileSize(result) >= fileSize(input) {
            try? FileManager.default.removeItem(at: result)
            throw ConversionError("\(input.lastPathComponent) can't be made any smaller")
        }
        return result
    }

    static func compressAnyway(_ input: URL, targetBytes: Int, output: URL?) throws -> URL {
        switch Formats.category(of: input) {
        case .image where ImageEngine.frameCount(input) > 1 && canonicalExtension(of: input) == "gif":
            return try animatedGIF(input, targetBytes: targetBytes, output: output ?? out(input, "gif"))
        case .image: return try image(input, targetBytes: targetBytes, output: output)
        case .video: return try video(input, targetBytes: targetBytes, output: output ?? out(input, canonicalExtension(of: input)))
        case .audio: return try audio(input, targetBytes: targetBytes, output: output)
        case .pdf: return try pdf(input, targetBytes: targetBytes, output: output ?? out(input, "pdf"))
        default: throw ConversionError("Compression isn't available for \(input.lastPathComponent)")
        }
    }

    static func out(_ input: URL, _ ext: String) -> URL { OutputNamer.output(for: input, ext: ext, suffix: " compressed") }

    // MARK: Image

    static func image(_ input: URL, targetBytes: Int, output: URL?) throws -> URL {
        let inExt = canonicalExtension(of: input)
        let ext = ImageEngine.utis[inExt] != nil || inExt == "webp" ? (inExt == "pdf" ? "jpg" : inExt) : "jpg"
        let output = output ?? out(input, ext)
        let original = try ImageEngine.load(input)
        let meta = ImageEngine.properties(input)
        func attempt(_ image: CGImage, _ quality: Double) throws -> Int {
            try ImageEngine.write(image, to: output, ext: ext, quality: quality, metadata: meta)
            return fileSize(output)
        }
        var image = original
        if ImageEngine.lossy.contains(ext) {
            // Binary search the highest quality that fits.
            var lo = 0.05, hi = 0.95, best: Double?
            for _ in 0..<7 {
                let mid = (lo + hi) / 2
                if try attempt(image, mid) <= targetBytes { best = mid; lo = mid } else { hi = mid }
            }
            if let best { _ = try attempt(image, best); return output }
        }
        // Lossless format, or lossy at minimum quality still too big: shrink pixels.
        let quality = 0.6
        var size = try attempt(image, quality)
        var tries = 0
        while size > targetBytes && tries < 8 && image.width > 16 {
            let factor = max(0.3, min(0.95, (Double(targetBytes) / Double(size)).squareRoot() * 0.95))
            image = ImageEngine.resized(original, width: Int(Double(image.width) * factor), height: Int(Double(image.height) * factor))
            size = try attempt(image, quality)
            tries += 1
        }
        return output
    }

    static func animatedGIF(_ input: URL, targetBytes: Int, output: URL) throws -> URL {
        var scale = 1.0
        for _ in 0..<5 {
            try MediaEngine.encode([input], output: output, ext: "gif", videoFilters: ["scale=iw*\(scale):-1"])
            let size = fileSize(output)
            if size <= targetBytes { break }
            scale *= max(0.4, (Double(targetBytes) / Double(size)).squareRoot())
        }
        return output
    }

    // MARK: Media

    static func video(_ input: URL, targetBytes: Int, output: URL) throws -> URL {
        let info = try MediaEngine.probe(input)
        guard info.duration > 0 else { throw ConversionError("Can't read video duration") }
        let ext = canonicalExtension(of: output)
        let totalKbps = Double(targetBytes) * 8 * 0.85 / info.duration / 1000
        let audioKbps = info.hasAudio ? min(96, max(16, totalKbps * 0.2)) : 0
        let videoKbps = max(16, totalKbps - audioKbps)
        try MediaEngine.encode([input], output: output, ext: ext,
                               extra: ["-maxrate", "\(Int(videoKbps * 1.2))k", "-bufsize", "\(Int(videoKbps * 2))k", "-map_metadata", "0"],
                               videoBitrate: "\(Int(videoKbps))k", audioBitrate: "\(Int(audioKbps))k")
        return output
    }

    static func audio(_ input: URL, targetBytes: Int, output: URL?) throws -> URL {
        let info = try MediaEngine.probe(input)
        guard info.duration > 0 else { throw ConversionError("Can't read audio duration") }
        let inExt = canonicalExtension(of: input)
        let ext = lossless.contains(inExt) || inExt == "aac" ? "m4a" : inExt
        let output = output ?? out(input, ext)
        let kbps = min(320, max(24, Double(targetBytes) * 8 * 0.97 / info.duration / 1000))
        try MediaEngine.encode([input], output: output, ext: ext, extra: ["-map_metadata", "0"], audioBitrate: "\(Int(kbps))k")
        return output
    }

    // MARK: PDF

    static func pdf(_ input: URL, targetBytes: Int, output: URL) throws -> URL {
        let doc = try PDFEngine.document(input)
        clearOutput(output)
        doc.write(to: output, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
        if fileSize(output) <= targetBytes && fileSize(output) > 0 { return output }
        // Rasterize pages to JPEG at decreasing quality until it fits.
        for (dpi, quality) in [(150.0, 0.7), (120.0, 0.55), (96.0, 0.45), (72.0, 0.35), (60.0, 0.25), (48.0, 0.2), (36.0, 0.15)] {
            try rasterPDF(input, dpi: dpi, quality: quality, output: output)
            if fileSize(output) <= targetBytes { break }
        }
        return output
    }

    static func rasterPDF(_ input: URL, dpi: Double, quality: Double, output: URL) throws {
        let count = PDFEngine.pageCount(input)
        let pages = try (0..<count).map { i -> CGImage in
            let page = try PDFEngine.renderPage(input, index: i, dpi: dpi)
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw ConversionError("JPEG encode failed") }
            CGImageDestinationAddImage(dest, ImageEngine.flatten(page), [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            CGImageDestinationFinalize(dest)
            // A JPEG-data-provider CGImage is embedded as DCT data as-is, keeping the PDF small.
            guard let provider = CGDataProvider(data: data),
                  let jpeg = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
                throw ConversionError("JPEG decode failed")
            }
            return jpeg
        }
        // Keep the original page size in points.
        var box = CGRect.zero
        clearOutput(output)
        guard let ctx = CGContext(output as CFURL, mediaBox: &box, nil), let doc = CGPDFDocument(input as CFURL) else {
            throw ConversionError("Can't create PDF")
        }
        for (i, image) in pages.enumerated() {
            var rect = doc.page(at: i + 1)?.getBoxRect(.cropBox) ?? CGRect(x: 0, y: 0, width: 612, height: 792)
            rect.origin = .zero
            if let angle = doc.page(at: i + 1)?.rotationAngle, angle % 180 != 0 { rect.size = CGSize(width: rect.height, height: rect.width) }
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &rect, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            ctx.draw(image, in: rect)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
