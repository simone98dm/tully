import AppKit
import CoreText

/// A document as semantic blocks: what Markdown, EPUB and XLSX exports are built from.
public struct TextBlock: Equatable {
    public enum Kind: Equatable { case heading(Int), paragraph, listItem }
    public struct Run: Equatable { public var text: String; public var bold: Bool; public var italic: Bool }
    public var kind: Kind
    public var runs: [Run]
    public var plain: String { runs.map(\.text).joined() }
}

/// Everything text-like goes through NSAttributedString.
public enum RichText {
    static let bodyFont = NSFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)

    // MARK: Reading

    public static func read(_ url: URL) throws -> NSAttributedString {
        switch canonicalExtension(of: url) {
        case "txt": return plain(try readPlainText(url))
        case "md": return try fromHTML(Markdown.html(try readPlainText(url)))
        case "textclipping": return plain(try readClipping(url))
        case "epub": return try fromHTML(try EPUB.html(from: url))
        case "pdf": return PDFEngine.attributedText(url)
        case "pages": return try viaAppleApp(url, app: .pages)
        default: return try viaTextutil(url)
        }
    }

    public static func plain(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: bodyFont])
    }

    static func readPlainText(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        return try String(contentsOf: url, encoding: .isoLatin1)
    }

    static func readClipping(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let utiData = plist?["UTI-Data"] as? [String: Any] ?? [:]
        if let text = utiData["public.utf8-plain-text"] as? String { return text }
        if let text = utiData["public.utf16-plain-text"] as? String { return text }
        throw ConversionError("Clipping has no text")
    }

    /// textutil handles docx/doc/rtf/rtfd/html/odt/webarchive out of process (thread safe, no WebKit here).
    static func viaTextutil(_ url: URL) throws -> NSAttributedString {
        try TempDir.with { dir in
            let rtf = dir.appendingPathComponent("out.rtf")
            try Shell.run("/usr/bin/textutil", ["-convert", "rtf", "-output", rtf.path, url.path])
            return try NSAttributedString(url: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                          documentAttributes: nil)
        }
    }

    public static func fromHTML(_ html: String) throws -> NSAttributedString {
        try TempDir.with { dir in
            let file = dir.appendingPathComponent("in.html")
            try html.write(to: file, atomically: true, encoding: .utf8)
            return try viaTextutil(file)
        }
    }

    static func viaAppleApp(_ url: URL, app: AppleApp) throws -> NSAttributedString {
        try TempDir.with { dir in
            let docx = dir.appendingPathComponent("out.docx")
            try AppleApps.export(url, to: docx, app: app, format: "Microsoft Word")
            return try viaTextutil(docx)
        }
    }

    // MARK: Writing

    public static func write(_ text: NSAttributedString, to url: URL, ext: String, title: String) throws {
        switch ext {
        case "txt": try text.string.write(to: url, atomically: true, encoding: .utf8)
        case "md": try markdown(blocks(text)).write(to: url, atomically: true, encoding: .utf8)
        case "pdf": try writePDF(text, to: url)
        case "epub": try EPUB.write(blocks(text), title: title, to: url)
        case "rtf":
            let data = try text.data(from: NSRange(location: 0, length: text.length),
                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try data.write(to: url)
        case "pages":
            try TempDir.with { dir in
                let docx = dir.appendingPathComponent("\(title).docx")
                try write(text, to: docx, ext: "docx", title: title)
                try AppleApps.saveNative(docx, to: url, app: .pages)
            }
        default: // docx, html, odt, doc
            try TempDir.with { dir in
                let rtf = dir.appendingPathComponent("in.rtf")
                try write(text, to: rtf, ext: "rtf", title: title)
                try Shell.run("/usr/bin/textutil", ["-convert", ext, "-output", url.path, rtf.path])
            }
        }
    }

    /// Paginates with CoreText onto US Letter pages.
    public static func writePDF(_ text: NSAttributedString, to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        clearOutput(url)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ConversionError("Can't create PDF") }
        let content = text.length == 0 ? plain(" ") : text
        let framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        let frameRect = box.insetBy(dx: 72, dy: 72)
        var location = 0
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            location += visible.length
        } while location < content.length
        ctx.closePDF()
    }

    // MARK: Semantic blocks

    public static func blocks(_ text: NSAttributedString) -> [TextBlock] {
        let base = bodySize(text)
        var result: [TextBlock] = []
        let ns = text.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { _, range, _, _ in
            guard range.length > 0 else { return }
            var runs: [TextBlock.Run] = []
            var maxSize: CGFloat = 0
            text.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let font = value as? NSFont ?? bodyFont
                let traits = font.fontDescriptor.symbolicTraits
                maxSize = max(maxSize, font.pointSize)
                runs.append(.init(text: ns.substring(with: runRange), bold: traits.contains(.bold), italic: traits.contains(.italic)))
            }
            let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let plainText = runs.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            guard !plainText.isEmpty else { return }
            var kind = TextBlock.Kind.paragraph
            let hasMarker = plainText.range(of: #"^([•◦▪]|\d+[.)])\s"#, options: .regularExpression) != nil
            if !(style?.textLists.isEmpty ?? true) || hasMarker {
                kind = .listItem
                runs = stripListMarker(runs)
            } else if plainText.count < 120 && maxSize >= base * 1.12 {
                kind = .heading(maxSize >= base * 1.6 ? 1 : maxSize >= base * 1.3 ? 2 : 3)
                runs = runs.map { .init(text: $0.text, bold: false, italic: $0.italic) }
            }
            result.append(TextBlock(kind: kind, runs: runs))
        }
        return result
    }

    /// Most common size among regular (non-bold) runs; headings are usually bold, so they don't skew short docs.
    static func bodySize(_ text: NSAttributedString) -> CGFloat {
        var regular: [CGFloat: Int] = [:], all: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let font = value as? NSFont ?? bodyFont
            all[font.pointSize, default: 0] += range.length
            if !font.fontDescriptor.symbolicTraits.contains(.bold) { regular[font.pointSize, default: 0] += range.length }
        }
        let counts = regular.isEmpty ? all : regular
        return counts.max { $0.value < $1.value }?.key ?? 12
    }

    /// textutil renders list markers inline as "\t•\t" / "\t1.\t"; drop them.
    static func stripListMarker(_ runs: [TextBlock.Run]) -> [TextBlock.Run] {
        guard var first = runs.first else { return runs }
        first.text = first.text.replacingOccurrences(of: #"^\s*([•◦▪\-*]|\d+[.)])\s+"#, with: "", options: .regularExpression)
        return [first] + runs.dropFirst()
    }

    public static func markdown(_ blocks: [TextBlock]) -> String {
        func inline(_ runs: [TextBlock.Run]) -> String {
            runs.map { run in
                let text = run.text.trimmingCharacters(in: .newlines)
                let core = text.trimmingCharacters(in: .whitespaces)
                guard !core.isEmpty, run.bold || run.italic else { return text }
                let mark = run.bold && run.italic ? "***" : run.bold ? "**" : "*"
                return text.replacingOccurrences(of: core, with: mark + core + mark)
            }.joined()
        }
        var lines: [String] = []
        for (i, block) in blocks.enumerated() {
            let body = inline(block.runs).trimmingCharacters(in: .whitespaces)
            switch block.kind {
            case .heading(let level): lines.append(String(repeating: "#", count: level) + " " + body)
            case .paragraph: lines.append(body)
            case .listItem: lines.append("- " + body)
            }
            let next = blocks.indices.contains(i + 1) ? blocks[i + 1].kind : nil
            if !(block.kind == .listItem && next == .listItem) { lines.append("") }
        }
        return lines.joined(separator: "\n")
    }

    public static func xhtml(_ blocks: [TextBlock]) -> String {
        func inline(_ runs: [TextBlock.Run]) -> String {
            runs.map { run in
                var s = run.text.trimmingCharacters(in: .newlines).xmlEscaped
                if run.italic { s = "<i>\(s)</i>" }
                if run.bold { s = "<b>\(s)</b>" }
                return s
            }.joined()
        }
        var out: [String] = []
        var inList = false
        for block in blocks {
            if block.kind != .listItem, inList { out.append("</ul>"); inList = false }
            switch block.kind {
            case .heading(let level): out.append("<h\(level)>\(inline(block.runs))</h\(level)>")
            case .paragraph: out.append("<p>\(inline(block.runs))</p>")
            case .listItem:
                if !inList { out.append("<ul>"); inList = true }
                out.append("<li>\(inline(block.runs))</li>")
            }
        }
        if inList { out.append("</ul>") }
        return out.joined(separator: "\n")
    }
}
