import AppKit
import PDFKit

public enum PDFEngine {
    public static func document(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw ConversionError("Can't open PDF \(url.lastPathComponent)") }
        if doc.isLocked { throw ConversionError("PDF is password protected") }
        return doc
    }

    public static func pageCount(_ url: URL) -> Int { PDFDocument(url: url)?.pageCount ?? 0 }

    /// Renders one page on white at `dpi`.
    public static func renderPage(_ url: URL, index: Int, dpi: CGFloat) throws -> CGImage {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: index + 1) else {
            throw ConversionError("Can't read PDF page \(index + 1)")
        }
        return try render(page, dpi: dpi)
    }

    static func render(_ page: CGPDFPage, dpi: CGFloat) throws -> CGImage {
        let box = page.getBoxRect(.cropBox)
        let rotated = page.rotationAngle % 180 != 0
        let scale = dpi / 72
        let size = CGSize(width: (rotated ? box.height : box.width) * scale, height: (rotated ? box.width : box.height) * scale)
        guard let ctx = ImageEngine.context(width: Int(size.width), height: Int(size.height)) else {
            throw ConversionError("Page too large to render")
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: CGSize(width: size.width / scale, height: size.height / scale)),
                                                 rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        guard let image = ctx.makeImage() else { throw ConversionError("Render failed") }
        return image
    }

    public static func attributedText(_ url: URL) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard let doc = PDFDocument(url: url) else { return result }
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if i > 0 { result.append(RichText.plain("\n\n")) }
            result.append(page.attributedString ?? RichText.plain(page.string ?? ""))
        }
        return result
    }

    public static func text(_ url: URL) -> String { attributedText(url).string }

    // MARK: Conversions

    public static func convert(_ input: URL, to ext: String, output: URL, title: String) throws -> URL {
        switch ext {
        case "jpg", "png": return try toImages(input, ext: ext, output: output)
        case "pptx":
            let doc = try document(input)
            let size = doc.page(at: 0)?.bounds(for: .cropBox).size ?? CGSize(width: 960, height: 540)
            let slides = try (0..<doc.pageCount).map { i -> PPTXSlide in
                let image = try renderPage(input, index: i, dpi: 150)
                return PPTXSlide(texts: [], image: try pngData(image))
            }
            try OOXML.writePPTX(slides, size: size, to: output)
        case "xlsx": try OOXML.writeXLSX([tableFromText(text(input))], to: output)
        default: try RichText.write(attributedText(input), to: output, ext: ext, title: title)
        }
        return output
    }

    /// One image per page at 300 DPI; several pages go in a folder named after the PDF.
    static func toImages(_ input: URL, ext: String, output: URL) throws -> URL {
        let count = pageCount(input)
        guard count > 0 else { throw ConversionError("PDF has no pages") }
        if count == 1 {
            try ImageEngine.write(try renderPage(input, index: 0, dpi: 300), to: output, ext: ext)
            return output
        }
        let base = OutputNamer.baseName(of: input)
        let folder = OutputNamer.unique(in: output.deletingLastPathComponent(), base: base, ext: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<count {
            let file = folder.appendingPathComponent("\(base)-\(i + 1).\(ext)")
            try ImageEngine.write(try renderPage(input, index: i, dpi: 300), to: file, ext: ext)
        }
        return folder
    }

    /// Each non-empty line is a row; tabs or runs of 2+ spaces separate columns.
    public static func tableFromText(_ text: String, name: String = "Sheet1") -> Sheet {
        let rows = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.components(separatedBy: "\t").flatMap { $0.components(separatedBy: "  ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return Sheet(name: name, rows: rows)
    }

    public static func pngData(_ image: CGImage) throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ConversionError("PNG encode failed")
        }
        return data
    }

    // MARK: Building PDFs

    /// Writes images as PDF pages, each page sized to its image (at 72 DPI-equivalent points, capped).
    public static func pdf(fromImages images: [CGImage], to url: URL, maxPageSide: CGFloat = 1200) throws {
        var box = CGRect.zero
        clearOutput(url)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ConversionError("Can't create PDF") }
        for image in images {
            let scale = min(1, maxPageSide / CGFloat(max(image.width, image.height)))
            var page = CGRect(x: 0, y: 0, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary
            ctx.beginPDFPage(info)
            ctx.draw(image, in: page)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
