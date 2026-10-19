import AppKit
import CoreText

public struct Sheet: Equatable, Sendable {
    public var name: String
    public var rows: [[String]]
    public init(name: String, rows: [[String]]) { self.name = name; self.rows = rows }
}

public enum Spreadsheet {
    public static func read(_ url: URL) throws -> [Sheet] {
        let name = OutputNamer.baseName(of: url)
        switch canonicalExtension(of: url) {
        case "csv": return [Sheet(name: name, rows: parseDelimited(try RichText.readPlainText(url), separator: ","))]
        case "tsv": return [Sheet(name: name, rows: parseDelimited(try RichText.readPlainText(url), separator: "\t"))]
        case "xlsx": return try OOXML.readXLSX(url)
        case "ods": return try readODS(url)
        default: // xls, numbers: let Numbers translate
            return try TempDir.with { dir in
                let xlsx = dir.appendingPathComponent("out.xlsx")
                try AppleApps.export(url, to: xlsx, app: .numbers, format: "Microsoft Excel")
                return try OOXML.readXLSX(xlsx)
            }
        }
    }

    public static func write(_ sheets: [Sheet], to url: URL, ext: String) throws {
        let first = sheets.first ?? Sheet(name: "Sheet1", rows: [])
        switch ext {
        case "csv": try formatDelimited(first.rows, separator: ",").write(to: url, atomically: true, encoding: .utf8)
        case "tsv": try formatDelimited(first.rows, separator: "\t").write(to: url, atomically: true, encoding: .utf8)
        case "xlsx": try OOXML.writeXLSX(sheets, to: url)
        case "ods": try writeODS(sheets, to: url)
        case "html": try html(sheets).write(to: url, atomically: true, encoding: .utf8)
        case "pdf": try writePDF(sheets, to: url)
        default: throw ConversionError("Unsupported spreadsheet output \(ext)")
        }
    }

    // MARK: Delimited text (RFC 4180)

    public static func parseDelimited(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, iterator = Array(text).makeIterator(), pending: Character?
        func next() -> Character? { if let p = pending { pending = nil; return p }; return iterator.next() }
        while let ch = next() {
            if quoted {
                if ch == "\"" {
                    if let following = next() { if following == "\"" { field.append("\"") } else { quoted = false; pending = following } }
                    else { quoted = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty {
                quoted = true
            } else if ch == separator {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r\n" || ch == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    public static func formatDelimited(_ rows: [[String]], separator: Character) -> String {
        rows.map { row in
            row.map { field in
                field.contains(separator) || field.contains("\"") || field.contains("\n")
                    ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
            }.joined(separator: String(separator))
        }.joined(separator: "\n") + "\n"
    }

    // MARK: ODS

    static func writeODS(_ sheets: [Sheet], to url: URL) throws {
        let tables = sheets.map { sheet in
            let rows = sheet.rows.map { row in
                "<table:table-row>" + row.map { value in
                    if let n = Double(value), !value.isEmpty {
                        return "<table:table-cell office:value-type=\"float\" office:value=\"\(n)\"><text:p>\(value.xmlEscaped)</text:p></table:table-cell>"
                    }
                    return "<table:table-cell office:value-type=\"string\"><text:p>\(value.xmlEscaped)</text:p></table:table-cell>"
                }.joined() + "</table:table-row>"
            }
            return "<table:table table:name=\"\(sheet.name.xmlEscaped)\">\(rows.joined())</table:table>"
        }
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
        xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" office:version="1.2">
        <office:body><office:spreadsheet>\(tables.joined())</office:spreadsheet></office:body></office:document-content>
        """
        let manifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
        <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>
        <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
        </manifest:manifest>
        """
        try Zip.write([("mimetype", "application/vnd.oasis.opendocument.spreadsheet".data),
                       ("content.xml", content.data), ("META-INF/manifest.xml", manifest.data)],
                      to: url, storedFirst: ["mimetype"])
    }

    static func readODS(_ url: URL) throws -> [Sheet] {
        try TempDir.with { dir in
            try Zip.extract(url, to: dir)
            let parser = ODSParser()
            let xml = XMLParser(data: try Data(contentsOf: dir.appendingPathComponent("content.xml")))
            xml.delegate = parser
            xml.parse()
            return parser.sheets
        }
    }

    final class ODSParser: NSObject, XMLParserDelegate {
        var sheets: [Sheet] = []
        private var row: [String] = [], cell = "", inCell = false, paragraphs = 0
        private var rowRepeat = 1, cellRepeat = 1
        // ponytail: cap repeats; ODS pads sheets with "1048576 empty rows" style runs.
        private let maxRepeat = 1000

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String]) {
            switch name {
            case "table:table": sheets.append(Sheet(name: a["table:name"] ?? "Sheet\(sheets.count + 1)", rows: []))
            case "table:table-row": row = []; rowRepeat = min(Int(a["table:number-rows-repeated"] ?? "") ?? 1, maxRepeat)
            case "table:table-cell", "table:covered-table-cell":
                cell = ""; inCell = true; paragraphs = 0
                cellRepeat = min(Int(a["table:number-columns-repeated"] ?? "") ?? 1, maxRepeat)
            case "text:p": if paragraphs > 0 { cell += "\n" }; paragraphs += 1
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if inCell { cell += string } }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "table:table-cell", "table:covered-table-cell":
                inCell = false
                row += Array(repeating: cell, count: cellRepeat)
            case "table:table-row":
                while row.last == "" { row.removeLast() }
                guard !sheets.isEmpty else { return }
                sheets[sheets.count - 1].rows += Array(repeating: row, count: row.isEmpty ? 1 : rowRepeat)
            case "table:table":
                while sheets[sheets.count - 1].rows.last?.isEmpty == true { sheets[sheets.count - 1].rows.removeLast() }
            default: break
            }
        }
    }

    // MARK: HTML / PDF

    static func html(_ sheets: [Sheet]) -> String {
        let tables = sheets.map { sheet in
            "<h2>\(sheet.name.xmlEscaped)</h2><table border=\"1\" cellspacing=\"0\" cellpadding=\"4\">" +
                sheet.rows.map { "<tr>" + $0.map { "<td>\($0.xmlEscaped)</td>" }.joined() + "</tr>" }.joined() + "</table>"
        }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"/></head><body>\(tables.joined())</body></html>"
    }

    /// Grid layout with CoreGraphics; columns sized to content, landscape when wide.
    static func writePDF(_ sheets: [Sheet], to url: URL) throws {
        let font = NSFont.systemFont(ofSize: 9)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let rowHeight: CGFloat = 16, padding: CGFloat = 4, margin: CGFloat = 36
        var box = CGRect(x: 0, y: 0, width: 792, height: 612)
        clearOutput(url)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { throw ConversionError("Can't create PDF") }
        for sheet in sheets {
            let columns = sheet.rows.map(\.count).max() ?? 0
            let widths = (0..<columns).map { c in
                min(220, sheet.rows.map { c < $0.count ? NSAttributedString(string: $0[c], attributes: attrs).size().width : 0 }.max() ?? 0) + 2 * padding
            }
            let scale = min(1, (box.width - 2 * margin) / max(widths.reduce(0, +), 1))
            var y = box.height
            ctx.beginPDFPage(nil)
            for row in sheet.rows.isEmpty ? [[sheet.name]] : sheet.rows {
                if y - rowHeight < margin { ctx.endPDFPage(); ctx.beginPDFPage(nil); y = box.height }
                if y == box.height { y -= margin }
                var x = margin
                for (c, width) in widths.enumerated() {
                    let cell = CGRect(x: x, y: y - rowHeight, width: width * scale, height: rowHeight)
                    ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1)); ctx.setLineWidth(0.5); ctx.stroke(cell)
                    if c < row.count {
                        let line = CTLineCreateWithAttributedString(NSAttributedString(string: row[c], attributes: attrs))
                        ctx.saveGState(); ctx.clip(to: cell)
                        ctx.textPosition = CGPoint(x: cell.minX + padding * scale, y: cell.minY + 5)
                        CTLineDraw(line, ctx)
                        ctx.restoreGState()
                    }
                    x += width * scale
                }
                y -= rowHeight
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
}
