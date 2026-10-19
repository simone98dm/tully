import Foundation

/// EPUB 3 reading (spine concatenation) and writing (one chapter per top-level heading).
public enum EPUB {
    public static func html(from url: URL) throws -> String {
        try TempDir.with { dir in
            try Zip.extract(url, to: dir)
            let container = try Data(contentsOf: dir.appendingPathComponent("META-INF/container.xml"))
            guard let opfPath = XMLTextCollector.parse(container, interesting: ["rootfile"]).first?.attributes["full-path"] else {
                throw ConversionError("EPUB has no package file")
            }
            let opfURL = dir.appendingPathComponent(opfPath)
            let opf = XMLTextCollector.parse(try Data(contentsOf: opfURL), interesting: ["item", "itemref"])
            var manifest: [String: String] = [:]
            for item in opf where item.name == "item" {
                if let id = item.attributes["id"], let href = item.attributes["href"] { manifest[id] = href }
            }
            let base = opfURL.deletingLastPathComponent()
            let bodies = opf.filter { $0.name == "itemref" }.compactMap { ref -> String? in
                guard let href = ref.attributes["idref"].flatMap({ manifest[$0] }),
                      let chapter = try? String(contentsOf: base.appendingPathComponent(href.removingPercentEncoding ?? href), encoding: .utf8)
                else { return nil }
                return body(of: chapter)
            }
            return "<html><head><meta charset=\"utf-8\"/></head><body>\(bodies.joined(separator: "\n"))</body></html>"
        }
    }

    static func body(of html: String) -> String {
        guard let start = html.range(of: "<body[^>]*>", options: [.regularExpression, .caseInsensitive]),
              let end = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) else { return html }
        return String(html[start.upperBound..<end.lowerBound])
    }

    public static func write(_ blocks: [TextBlock], title: String, to url: URL) throws {
        let chapters = split(blocks)
        let id = "urn:uuid:\(UUID().uuidString)"
        var files: [(String, Data)] = [
            ("mimetype", "application/epub+zip".data),
            ("META-INF/container.xml", """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """.data),
        ]
        let names = chapters.indices.map { "chapter\($0 + 1).xhtml" }
        for (i, chapter) in chapters.enumerated() {
            files.append(("OEBPS/\(names[i])", page(title: chapter.title ?? title, body: RichText.xhtml(chapter.blocks)).data))
        }
        let navItems = chapters.enumerated().map { i, c in "<li><a href=\"\(names[i])\">\((c.title ?? "Chapter \(i + 1)").xmlEscaped)</a></li>" }
        files.append(("OEBPS/nav.xhtml", page(title: title, body: "<nav epub:type=\"toc\" id=\"toc\"><ol>\(navItems.joined())</ol></nav>").data))
        let manifest = names.enumerated().map { "<item id=\"c\($0)\" href=\"\($1)\" media-type=\"application/xhtml+xml\"/>" }
        let spine = names.indices.map { "<itemref idref=\"c\($0)\"/>" }
        files.append(("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:identifier id="bookid">\(id)</dc:identifier><dc:title>\(title.xmlEscaped)</dc:title><dc:language>en</dc:language>
        <meta property="dcterms:modified">\(ISO8601DateFormatter().string(from: Date()).prefix(19))Z</meta>
        </metadata>
        <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\(manifest.joined())</manifest>
        <spine>\(spine.joined())</spine>
        </package>
        """.data))
        try Zip.write(files, to: url, storedFirst: ["mimetype"])
    }

    struct Chapter { var title: String?; var blocks: [TextBlock] }

    static func split(_ blocks: [TextBlock]) -> [Chapter] {
        var chapters: [Chapter] = []
        for block in blocks {
            if block.kind == .heading(1) || chapters.isEmpty {
                chapters.append(Chapter(title: block.kind == .heading(1) ? block.plain : nil, blocks: []))
            }
            chapters[chapters.count - 1].blocks.append(block)
        }
        return chapters.isEmpty ? [Chapter(title: nil, blocks: [])] : chapters
    }

    static func page(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><meta charset="utf-8"/><title>\(title.xmlEscaped)</title></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}
