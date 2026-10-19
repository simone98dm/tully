import Foundation

/// Small Markdown -> HTML renderer covering the common subset (headings, lists, quotes, code, emphasis, links).
public enum Markdown {
    public static func html(_ markdown: String, title: String = "") -> String {
        var out: [String] = []
        var paragraph: [String] = []
        var list: String?
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty { out.append("<p>\(inline(paragraph.joined(separator: " ")))</p>") }
            paragraph = []
        }
        func closeList() {
            if let tag = list { out.append("</\(tag)>") }
            list = nil
        }
        func openList(_ tag: String) {
            if list != tag { closeList(); out.append("<\(tag)>"); list = tag }
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushParagraph(); closeList()
                out.append(inCode ? "</code></pre>" : "<pre><code>")
                inCode.toggle()
                continue
            }
            if inCode { out.append(raw.xmlEscaped); continue }
            if line.isEmpty { flushParagraph(); closeList(); continue }

            if let level = headingLevel(line) {
                flushParagraph(); closeList()
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                out.append("<h\(level)>\(inline(text))</h\(level)>")
            } else if let item = strip(line, prefixes: ["- ", "* ", "+ "]) {
                flushParagraph(); openList("ul"); out.append("<li>\(inline(item))</li>")
            } else if let match = line.range(of: #"^\d+[.)] "#, options: .regularExpression) {
                flushParagraph(); openList("ol"); out.append("<li>\(inline(String(line[match.upperBound...])))</li>")
            } else if let quote = strip(line, prefixes: ["> ", ">"]) {
                flushParagraph(); closeList(); out.append("<blockquote><p>\(inline(quote))</p></blockquote>")
            } else if line.allSatisfy({ $0 == "-" || $0 == "*" }) && line.count >= 3 {
                flushParagraph(); closeList(); out.append("<hr/>")
            } else {
                closeList(); paragraph.append(line)
            }
        }
        flushParagraph(); closeList()
        if inCode { out.append("</code></pre>") }
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"/><title>\(title.xmlEscaped)</title></head>
        <body>
        \(out.joined(separator: "\n"))
        </body></html>
        """
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    static func strip(_ line: String, prefixes: [String]) -> String? {
        prefixes.first { line.hasPrefix($0) }.map { String(line.dropFirst($0.count)) }
    }

    /// Inline spans: code, bold, italic, links. Escapes HTML first.
    static func inline(_ text: String) -> String {
        var s = text.xmlEscaped
        let rules: [(String, String)] = [
            (#"`([^`]+)`"#, "<code>$1</code>"),
            (#"\*\*([^*]+)\*\*"#, "<b>$1</b>"),
            (#"__([^_]+)__"#, "<b>$1</b>"),
            (#"\*([^*]+)\*"#, "<i>$1</i>"),
            (#"(?<![A-Za-z0-9])_([^_]+)_(?![A-Za-z0-9])"#, "<i>$1</i>"),
            (#"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s
    }
}
