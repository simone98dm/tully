import Foundation

/// Entry point for format conversion: picks the engine from the input's category.
public enum Converter {
    /// Converts `input` to `target`, writing beside it (or into `outputDir`). Returns the created file or folder.
    @discardableResult
    public static func convert(_ input: URL, to target: String, outputDir: URL? = nil) throws -> URL {
        guard let category = Formats.category(of: input) else {
            throw ConversionError("\(input.lastPathComponent) isn't a supported file type")
        }
        guard Formats.targets(for: input).contains(target) else {
            throw ConversionError("Can't convert \(canonicalExtension(of: input).uppercased()) to \(Formats.label(for: target))")
        }
        let output = OutputNamer.output(for: input, ext: target == "folder" ? nil : target, dir: outputDir)
        do {
            return try run(category, input, target, output)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    static func run(_ category: FileCategory, _ input: URL, _ target: String, _ output: URL) throws -> URL {
        let title = OutputNamer.baseName(of: input)
        switch category {
        case .image: try ImageEngine.convert(input, to: target, output: output)
        case .video, .audio: try MediaEngine.convert(input, to: target, output: output)
        case .pdf: return try PDFEngine.convert(input, to: target, output: output, title: title)
        case .document, .epub: try RichText.write(try RichText.read(input), to: output, ext: target, title: title)
        case .slides: return try Slides.convert(input, to: target, output: output)
        case .spreadsheet: try Spreadsheet.write(try Spreadsheet.read(input), to: output, ext: target)
        case .subtitle: try Subtitles.convert(input, to: target, output: output)
        case .archive: try Archive.convert(input, to: target, output: output)
        }
        return output
    }
}

public enum Slides {
    public static func convert(_ input: URL, to ext: String, output: URL) throws -> URL {
        if canonicalExtension(of: input) != "pptx" {
            // .ppt / .key: Keynote renders it to PDF, then reuse the PDF path.
            return try TempDir.with { dir in
                let pdf = dir.appendingPathComponent(OutputNamer.baseName(of: input) + ".pdf")
                try AppleApps.export(input, to: pdf, app: .keynote, format: "PDF")
                if ext == "pdf" { try FileManager.default.moveItem(at: pdf, to: output); return output }
                return try PDFEngine.toImages(pdf, ext: ext, output: output)
            }
        }
        let deck = try OOXML.readPPTX(input)
        guard !deck.slides.isEmpty else { throw ConversionError("Presentation has no slides") }
        let images = try deck.slides.map { try OOXML.render($0, size: deck.size) }
        if ext == "pdf" {
            try PDFEngine.pdf(fromImages: images, to: output, maxPageSide: max(deck.size.width, deck.size.height))
            return output
        }
        if images.count == 1 {
            try ImageEngine.write(images[0], to: output, ext: ext)
            return output
        }
        let base = OutputNamer.baseName(of: input)
        let folder = OutputNamer.unique(in: output.deletingLastPathComponent(), base: base, ext: nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (i, image) in images.enumerated() {
            try ImageEngine.write(image, to: folder.appendingPathComponent("\(base)-\(i + 1).\(ext)"), ext: ext)
        }
        return folder
    }
}
