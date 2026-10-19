import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case image, video, audio, pdf, document, epub, slides, spreadsheet, subtitle, archive
}

/// Canonical extension of a file, folding aliases (jpeg -> jpg, tgz -> tar.gz ...).
public func canonicalExtension(of url: URL) -> String {
    let name = url.lastPathComponent.lowercased()
    if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return "tar.gz" }
    return Formats.aliases[url.pathExtension.lowercased()] ?? url.pathExtension.lowercased()
}

public enum Formats {
    static let aliases: [String: String] = [
        "jpeg": "jpg", "tif": "tiff", "heif": "heic", "htm": "html", "aif": "aiff",
        "markdown": "md", "m4v": "mp4", "text": "txt", "tgz": "tar.gz", "oga": "ogg",
    ]

    /// Readable extensions per category.
    static let readable: [FileCategory: [String]] = [
        .image: ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "svg"],
        .video: ["mp4", "mov", "mkv", "webm", "avi", "wmv"],
        .audio: ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "aac"],
        .pdf: ["pdf"],
        .document: ["docx", "doc", "pages", "md", "txt", "rtf", "rtfd", "html", "odt", "textclipping"],
        .epub: ["epub"],
        .slides: ["pptx", "ppt", "key"],
        .spreadsheet: ["xlsx", "xls", "ods", "csv", "tsv", "numbers"],
        .subtitle: ["srt", "vtt"],
        .archive: ["zip", "tar", "tar.gz", "gz", "rar"],
    ]

    /// Output targets per input category (the input's own extension is removed).
    static let targets: [FileCategory: [String]] = [
        .image: ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "gif", "pdf"],
        .video: ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif", "mp3", "m4a", "wav"],
        .audio: ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"],
        .pdf: ["docx", "pages", "pptx", "xlsx", "jpg", "png", "epub", "txt", "md", "html", "rtf"],
        .document: ["docx", "pages", "md", "txt", "epub", "html", "pdf", "rtf", "odt"],
        .epub: ["pdf", "docx", "txt", "md", "html"],
        .slides: ["pdf", "jpg", "png"],
        .spreadsheet: ["xlsx", "ods", "csv", "tsv", "pdf", "html"],
        .subtitle: ["srt", "vtt", "txt"],
        .archive: ["zip", "tar", "tar.gz", "folder"],
    ]

    /// Extra cross-category targets (animated GIF -> video).
    static let extraTargets: [String: [String]] = ["gif": ["mp4", "webm", "mov"]]

    /// Write-only extras that are not conversion inputs (svg is input only, etc.).
    public static let displayNames: [String: String] = [
        "tar.gz": "GZIP", "folder": "Extract", "textclipping": "Clipping", "md": "Markdown",
    ]

    public static func category(of url: URL) -> FileCategory? {
        let ext = canonicalExtension(of: url)
        return FileCategory.allCases.first { readable[$0]?.contains(ext) == true }
    }

    public static func targets(for url: URL) -> [String] {
        guard let category = category(of: url) else { return [] }
        let ext = canonicalExtension(of: url)
        let base = (targets[category] ?? []) + (extraTargets[ext] ?? [])
        return base.filter { $0 != ext }
    }

    /// Targets shared by every file in a batch, in the first file's order.
    public static func commonTargets(for urls: [URL]) -> [String] {
        guard let first = urls.first else { return [] }
        let sets = urls.dropFirst().map { Set(targets(for: $0)) }
        return targets(for: first).filter { target in sets.allSatisfy { $0.contains(target) } }
    }

    public static func label(for target: String) -> String {
        displayNames[target] ?? target.uppercased()
    }

    /// Every (input extension, target) pair the engine claims to support.
    public static var allConversions: [(String, String)] {
        FileCategory.allCases.flatMap { category in
            (readable[category] ?? []).flatMap { ext in
                ((targets[category] ?? []) + (extraTargets[ext] ?? [])).filter { $0 != ext }.map { (ext, $0) }
            }
        }
    }
}

public enum OutputNamer {
    /// `dir/name.ext`, or `dir/name 2.ext`, `dir/name 3.ext` ... when taken.
    public static func unique(in dir: URL, base: String, ext: String?) -> URL {
        let fm = FileManager.default
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            return dir.appendingPathComponent(ext.map { "\(name).\($0)" } ?? name)
        }
        var n = 1
        while fm.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }

    /// File name without its (possibly double) extension.
    public static func baseName(of url: URL) -> String {
        let name = url.lastPathComponent
        for suffix in [".tar.gz", ".tgz"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Output beside the input (or in `dir`), with a new extension and optional suffix.
    public static func output(for input: URL, ext: String?, suffix: String = "", dir: URL? = nil) -> URL {
        unique(in: dir ?? input.deletingLastPathComponent(), base: baseName(of: input) + suffix, ext: ext)
    }
}
