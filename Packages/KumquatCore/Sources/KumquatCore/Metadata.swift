import Foundation
import ImageIO
import PDFKit

/// Read / edit / strip metadata for images, audio, video and PDF.
public enum Metadata {
    /// Editable fields per category, as (key, label).
    public static func fields(for category: FileCategory?) -> [(String, String)] {
        switch category {
        case .image: return [("title", "Title"), ("description", "Description"), ("artist", "Artist"), ("copyright", "Copyright"), ("date", "Date Taken")]
        case .audio, .video: return [("title", "Title"), ("artist", "Artist"), ("album", "Album"), ("date", "Year"), ("genre", "Genre"), ("comment", "Comment")]
        case .pdf: return [("title", "Title"), ("author", "Author"), ("subject", "Subject"), ("keywords", "Keywords")]
        default: return []
        }
    }

    // MARK: Read

    public static func read(_ url: URL) throws -> [String: String] {
        switch Formats.category(of: url) {
        case .image: return readImage(url)
        case .audio, .video:
            let tags = try MediaEngine.probe(url).tags
            var result: [String: String] = [:]
            for (key, value) in tags { result[key.lowercased()] = value }
            return result
        case .pdf:
            let attrs = try PDFEngine.document(url).documentAttributes ?? [:]
            var result: [String: String] = [:]
            let map: [(PDFDocumentAttribute, String)] = [(.titleAttribute, "title"), (.authorAttribute, "author"), (.subjectAttribute, "subject"),
                                                        (.keywordsAttribute, "keywords"), (.creatorAttribute, "creator"), (.producerAttribute, "producer")]
            for (attr, key) in map {
                if let s = attrs[attr] as? String { result[key] = s }
                if let list = attrs[attr] as? [String] { result[key] = list.joined(separator: ", ") }
            }
            return result
        default: throw ConversionError("No metadata support for \(url.lastPathComponent)")
        }
    }

    static func readImage(_ url: URL) -> [String: String] {
        let props = ImageEngine.properties(url)
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        var result: [String: String] = [:]
        result["title"] = iptc[kCGImagePropertyIPTCObjectName] as? String
        result["description"] = tiff[kCGImagePropertyTIFFImageDescription] as? String
        result["artist"] = tiff[kCGImagePropertyTIFFArtist] as? String
        result["copyright"] = tiff[kCGImagePropertyTIFFCopyright] as? String
        result["date"] = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        result["camera"] = [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]].compactMap { $0 as? String }.joined(separator: " ")
        result["gps"] = props[kCGImagePropertyGPSDictionary] != nil ? "yes" : nil
        result["width"] = (props[kCGImagePropertyPixelWidth] as? Int).map(String.init)
        result["height"] = (props[kCGImagePropertyPixelHeight] as? Int).map(String.init)
        return result.filter { !$0.value.isEmpty }
    }

    // MARK: Write

    /// Writes a copy with `values` applied; empty values clear the field.
    public static func write(_ url: URL, values: [String: String], output: URL? = nil) throws -> URL {
        let ext = canonicalExtension(of: url)
        let output = output ?? OutputNamer.output(for: url, ext: ext, suffix: " edited")
        switch Formats.category(of: url) {
        case .image: try writeImage(url, values: values, output: output)
        case .audio, .video:
            let tags = values.flatMap { ["-metadata", "\($0.key)=\($0.value)"] }
            try Shell.ffmpeg(["-i", url.path, "-map", "0", "-c", "copy", "-map_metadata", "0"] + tags + [output.path])
        case .pdf:
            let doc = try PDFEngine.document(url)
            var attrs = doc.documentAttributes ?? [:]
            let map: [String: PDFDocumentAttribute] = ["title": .titleAttribute, "author": .authorAttribute, "subject": .subjectAttribute, "keywords": .keywordsAttribute]
            for (key, value) in values {
                guard let attr = map[key] else { continue }
                attrs[attr] = key == "keywords" ? value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } as Any : value
            }
            doc.documentAttributes = attrs
            guard doc.write(to: output) else { throw ConversionError("Failed writing PDF") }
        default: throw ConversionError("No metadata support for \(url.lastPathComponent)")
        }
        return output
    }

    static func writeImage(_ url: URL, values: [String: String], output: URL) throws {
        var props = ImageEngine.properties(url)
        var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]
        func set(_ dict: inout [CFString: Any], _ key: CFString, _ field: String) {
            guard let value = values[field] else { return }
            dict[key] = value.isEmpty ? nil : value
        }
        set(&iptc, kCGImagePropertyIPTCObjectName, "title")
        set(&tiff, kCGImagePropertyTIFFImageDescription, "description")
        set(&iptc, kCGImagePropertyIPTCCaptionAbstract, "description")
        set(&tiff, kCGImagePropertyTIFFArtist, "artist")
        set(&tiff, kCGImagePropertyTIFFCopyright, "copyright")
        set(&iptc, kCGImagePropertyIPTCCopyrightNotice, "copyright")
        set(&exif, kCGImagePropertyExifDateTimeOriginal, "date")
        props[kCGImagePropertyTIFFDictionary] = tiff
        props[kCGImagePropertyExifDictionary] = exif
        props[kCGImagePropertyIPTCDictionary] = iptc
        try ImageEngine.write(try ImageEngine.load(url), to: output, ext: imageOutputExt(url), quality: 0.95, metadata: props)
    }

    static func imageOutputExt(_ url: URL) -> String {
        let ext = canonicalExtension(of: url)
        return ImageEngine.utis[ext] != nil || ext == "webp" ? ext : "png"
    }

    // MARK: Strip

    public static func strip(_ url: URL, output: URL? = nil) throws -> URL {
        let ext = canonicalExtension(of: url)
        let output = output ?? OutputNamer.output(for: url, ext: Formats.category(of: url) == .image ? imageOutputExt(url) : ext, suffix: " clean")
        switch Formats.category(of: url) {
        case .image: try ImageEngine.write(try ImageEngine.load(url), to: output, ext: imageOutputExt(url), quality: 0.95, metadata: nil)
        case .audio, .video:
            try Shell.ffmpeg(["-i", url.path, "-map", "0", "-c", "copy", "-map_metadata", "-1", "-map_chapters", "-1",
                              "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact", output.path])
        case .pdf:
            let doc = try PDFEngine.document(url)
            doc.documentAttributes = [:]
            guard doc.write(to: output) else { throw ConversionError("Failed writing PDF") }
        default: throw ConversionError("No metadata support for \(url.lastPathComponent)")
        }
        return output
    }
}
