import Foundation

/// Zip containers (EPUB, OOXML) via the system zip/ditto tools.
public enum Zip {
    /// Zips the contents of `dir` into `output`. Files in `storedFirst` go first, uncompressed (EPUB mimetype).
    public static func create(from dir: URL, to output: URL, storedFirst: [String] = []) throws {
        try? FileManager.default.removeItem(at: output)
        for name in storedFirst {
            try Shell.run("/usr/bin/zip", ["-X0q", output.path, name], cwd: dir)
        }
        let excludes = storedFirst.flatMap { ["-x", $0] }
        try Shell.run("/usr/bin/zip", ["-Xr9Dq", output.path, "."] + excludes, cwd: dir)
    }

    public static func extract(_ archive: URL, to dir: URL) throws {
        try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
    }

    /// Writes `files` (relative path -> contents) into a new zip.
    public static func write(_ files: [(String, Data)], to output: URL, storedFirst: [String] = []) throws {
        try TempDir.with { dir in
            for (path, data) in files {
                let url = dir.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
            try create(from: dir, to: output, storedFirst: storedFirst)
        }
    }
}

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    var data: Data { Data(utf8) }
}

/// Minimal DOM-less XML reader: collects elements (by local name) with their nested text.
final class XMLTextCollector: NSObject, XMLParserDelegate {
    struct Element { var name: String; var attributes: [String: String]; var text: String }
    private(set) var elements: [Element] = []
    private var open: [Int] = []
    private let interesting: Set<String>

    init(interesting: Set<String>) { self.interesting = interesting }

    static func parse(_ data: Data, interesting: Set<String>) -> [Element] {
        let collector = XMLTextCollector(interesting: interesting)
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.elements
    }

    private static func local(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        guard interesting.contains(Self.local(name)) else { return }
        elements.append(Element(name: Self.local(name), attributes: attributes, text: ""))
        open.append(elements.count - 1)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        for index in open { elements[index].text += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if interesting.contains(Self.local(name)) { open.removeLast() }
    }
}
