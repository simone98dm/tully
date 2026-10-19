import AppKit
import CoreImage
import Foundation
import PDFKit

public enum PDFTools {
    public static func merge(_ urls: [URL]) throws -> URL {
        guard urls.count >= 2 else { throw ConversionError("Choose at least two files to merge") }
        let result = PDFDocument()
        for url in urls {
            if Formats.category(of: url) == .image {
                // Images can be merged in too: one page each.
                guard let page = PDFPage(image: NSImage(cgImage: try ImageEngine.load(url), size: .zero)) else { continue }
                result.insert(page, at: result.pageCount)
                continue
            }
            let doc = try PDFEngine.document(url)
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) { result.insert(page, at: result.pageCount) }
            }
        }
        let output = OutputNamer.output(for: urls[0], ext: "pdf", suffix: " merged")
        guard result.write(to: output) else { throw ConversionError("Failed writing PDF") }
        return output
    }

    /// Splits into one file per page, or per range when `ranges` (1-based, "1-3, 5") is given.
    public static func split(_ url: URL, ranges: String? = nil) throws -> [URL] {
        let doc = try PDFEngine.document(url)
        let groups: [[Int]]
        if let ranges, !ranges.trimmingCharacters(in: .whitespaces).isEmpty {
            groups = try pageGroups(ranges, pageCount: doc.pageCount)
        } else {
            groups = (0..<doc.pageCount).map { [$0] }
        }
        return try groups.enumerated().map { index, pages in
            let part = PDFDocument()
            for p in pages { if let page = doc.page(at: p) { part.insert(page, at: part.pageCount) } }
            let label = pages.count == 1 ? "page \(pages[0] + 1)" : "pages \(pages[0] + 1)-\(pages[pages.count - 1] + 1)"
            let output = OutputNamer.output(for: url, ext: "pdf", suffix: " \(groups.count == doc.pageCount ? label : "part \(index + 1)")")
            guard part.write(to: output) else { throw ConversionError("Failed writing PDF") }
            return output
        }
    }

    /// "1-3, 5" -> [[0,1,2],[4]] with bounds checking.
    public static func pageGroups(_ text: String, pageCount: Int) throws -> [[Int]] {
        try text.split(separator: ",").map { part in
            let bounds = part.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard let first = bounds.first, let last = bounds.last, bounds.count <= 2,
                  first >= 1, last <= pageCount, first <= last else {
                throw ConversionError("Invalid page range \"\(part.trimmingCharacters(in: .whitespaces))\" (document has \(pageCount) pages)")
            }
            return Array((first - 1)...(last - 1))
        }
    }

    public struct PageEdit: Equatable, Sendable {
        public var index: Int         // source page, 0-based
        public var rotation: Int      // extra degrees clockwise
        public init(index: Int, rotation: Int = 0) { self.index = index; self.rotation = rotation }
    }

    /// Writes pages in the given order; omitted pages are deleted.
    public static func reorganize(_ url: URL, pages: [PageEdit]) throws -> URL {
        guard !pages.isEmpty else { throw ConversionError("Keep at least one page") }
        let doc = try PDFEngine.document(url)
        let result = PDFDocument()
        for edit in pages {
            guard let page = doc.page(at: edit.index)?.copy() as? PDFPage else {
                throw ConversionError("Page \(edit.index + 1) doesn't exist")
            }
            page.rotation = ((page.rotation + edit.rotation) % 360 + 360) % 360
            result.insert(page, at: result.pageCount)
        }
        let output = OutputNamer.output(for: url, ext: "pdf", suffix: " reorganized")
        guard result.write(to: output) else { throw ConversionError("Failed writing PDF") }
        return output
    }

    /// Parses "3, 1, 2" (1-based) into an order for `reorganize`.
    public static func order(_ text: String, pageCount: Int) throws -> [PageEdit] {
        try text.split(separator: ",").map { item in
            guard let n = Int(item.trimmingCharacters(in: .whitespaces)), (1...pageCount).contains(n) else {
                throw ConversionError("Invalid page \"\(item.trimmingCharacters(in: .whitespaces))\"")
            }
            return PageEdit(index: n - 1)
        }
    }

    public static func rotate(_ url: URL, degrees: Int) throws -> URL {
        let count = try PDFEngine.document(url).pageCount
        let output = try reorganize(url, pages: (0..<count).map { PageEdit(index: $0, rotation: degrees) })
        let renamed = OutputNamer.output(for: url, ext: "pdf", suffix: " rotated")
        try FileManager.default.moveItem(at: output, to: renamed)
        return renamed
    }
}

public enum ImageTools {
    public static func resize(_ url: URL, percent: Double) throws -> URL {
        guard percent > 0 else { throw ConversionError("Scale must be positive") }
        let image = try ImageEngine.load(url)
        let w = max(1, Int((Double(image.width) * percent / 100).rounded()))
        let h = max(1, Int((Double(image.height) * percent / 100).rounded()))
        return try write(ImageEngine.resized(image, width: w, height: h), like: url, suffix: " \(w)x\(h)")
    }

    public static func rotate(_ url: URL, degrees: Int) throws -> URL {
        try write(try PhotoEditor.transform(try ImageEngine.load(url), rotation: degrees, flip: false), like: url, suffix: " rotated")
    }

    public static func flip(_ url: URL, vertical: Bool) throws -> URL {
        let image = try ImageEngine.load(url)
        let flipped = vertical ? try PhotoEditor.flipVertical(image) : try PhotoEditor.transform(image, rotation: 0, flip: true)
        return try write(flipped, like: url, suffix: " flipped")
    }

    static func write(_ image: CGImage, like url: URL, suffix: String) throws -> URL {
        let ext = Metadata.imageOutputExt(url)
        let output = OutputNamer.output(for: url, ext: ext, suffix: suffix)
        try ImageEngine.write(image, to: output, ext: ext, quality: 0.92, metadata: ImageEngine.properties(url))
        return output
    }

    /// QR (and other CoreImage-detectable) codes in an image or the first PDF page.
    public static func readQR(_ url: URL) throws -> [String] {
        let image = try ImageEngine.load(url)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: CIImage(cgImage: image)) ?? []
        return features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }

    public static func toPDF(_ urls: [URL]) throws -> URL {
        let images = try urls.map(ImageEngine.load)
        let output = OutputNamer.output(for: urls[0], ext: "pdf", suffix: urls.count > 1 ? " and \(urls.count - 1) more" : "")
        try PDFEngine.pdf(fromImages: images, to: output)
        return output
    }

    /// Grid collage: images fit into equal cells on white.
    public static func collage(_ urls: [URL], columns: Int, cell: Int = 800, spacing: Int = 16) throws -> URL {
        guard !urls.isEmpty else { throw ConversionError("Choose images for the collage") }
        let images = try urls.map(ImageEngine.load)
        let cols = max(1, min(columns, images.count)), rows = Int((Double(images.count) / Double(cols)).rounded(.up))
        let width = cols * cell + (cols + 1) * spacing, height = rows * cell + (rows + 1) * spacing
        guard let ctx = ImageEngine.context(width: width, height: height) else { throw ConversionError("Collage too large") }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        for (i, image) in images.enumerated() {
            let col = i % cols, row = i / cols
            let scale = min(Double(cell) / Double(image.width), Double(cell) / Double(image.height))
            let w = Double(image.width) * scale, h = Double(image.height) * scale
            let x = Double(spacing + col * (cell + spacing)) + (Double(cell) - w) / 2
            let yTop = Double(spacing + row * (cell + spacing)) + (Double(cell) - h) / 2
            ctx.draw(image, in: CGRect(x: x, y: Double(height) - yTop - h, width: w, height: h))
        }
        guard let result = ctx.makeImage() else { throw ConversionError("Collage render failed") }
        let output = OutputNamer.output(for: urls[0], ext: "jpg", suffix: " collage")
        try ImageEngine.write(result, to: output, ext: "jpg", quality: 0.9)
        return output
    }
}
