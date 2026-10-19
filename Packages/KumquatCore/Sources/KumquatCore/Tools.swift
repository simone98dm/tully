import Foundation

/// The tools wheel: every tool, its applicability, parameters and action.
public enum Tools {
    static let media: Set<FileCategory> = [.video, .audio]
    static let compressible: Set<FileCategory> = [.image, .video, .audio, .pdf]
    static let rotations = ["90° Right", "90° Left", "180°"]
    static func degrees(_ choice: String) -> Int { choice == "90° Left" ? 270 : choice == "180°" ? 180 : 90 }

    static func duration(_ urls: [URL]) -> Double { urls.first.flatMap { try? MediaEngine.probe($0).duration } ?? 0 }
    static func fmt(_ t: Double) -> String { String(format: "%.2f", t) }

    public static let all: [Tool] = [
        Tool("compress", "Compress", symbol: "arrow.down.right.and.arrow.up.left", compressible,
             parameters: { _ in [ToolParameter("percent", "Target size", .slider(min: 10, max: 90, step: 5, unit: "% of original"), default: "50")] }) { urls, p in
            let percent = try p.double("percent")
            return try eachFile(urls) { try Compression.compress($0, targetBytes: Int(Double(Compression.fileSize($0)) * percent / 100)) }
        },
        Tool("compress-size", "Compress to Size", symbol: "scalemass", compressible,
             parameters: { urls in
                 let mb = Double(urls.first.map(Compression.fileSize) ?? 0) / 2_000_000
                 // 3 decimals = KB precision, so small files get a real half-size default.
                 return [ToolParameter("size", "Maximum size", .number(unit: "MB"), default: String(format: "%.3f", max(mb, 0.001)))]
             }) { urls, p in
            let bytes = Int(try p.double("size") * 1_000_000)
            return try eachFile(urls) { try Compression.compress($0, targetBytes: bytes) }
        },
        Tool("resize", "Resize", symbol: "arrow.up.left.and.down.right.magnifyingglass", [.image],
             parameters: { _ in [ToolParameter("percent", "Scale", .slider(min: 5, max: 100, step: 5, unit: "%"), default: "50")] }) { urls, p in
            let percent = try p.double("percent")
            return try eachFile(urls) { try ImageTools.resize($0, percent: percent) }
        },
        Tool("rotate", "Rotate", symbol: "rotate.right", [.image, .video, .pdf],
             parameters: { _ in [ToolParameter("angle", "Rotation", .choice(rotations), default: rotations[0])] }) { urls, p in
            let deg = degrees(p.string("angle"))
            return try eachFile(urls) { url in
                switch Formats.category(of: url) {
                case .video: return try MediaTools.rotate(url, degrees: deg)
                case .pdf: return try PDFTools.rotate(url, degrees: deg)
                default: return try ImageTools.rotate(url, degrees: deg)
                }
            }
        },
        Tool("flip", "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", [.image, .video],
             parameters: { _ in [ToolParameter("axis", "Direction", .choice(["Horizontal", "Vertical"]), default: "Horizontal")] }) { urls, p in
            let axis = p.string("axis")
            return try eachFile(urls) { url in
                Formats.category(of: url) == .video ? try MediaTools.rotate(url, degrees: 0, flip: axis)
                                                    : try ImageTools.flip(url, vertical: axis == "Vertical")
            }
        },
        photoTool("crop", "Crop", "crop", .crop),
        photoTool("adjust", "Adjust", "slider.horizontal.3", .adjust),
        photoTool("annotate", "Annotate", "pencil.tip.crop.circle", .annotate),
        photoTool("redact", "Redact", "eye.slash", .redact),
        Tool("qr", "Read QR Code", symbol: "qrcode.viewfinder", [.image, .pdf]) { urls, _ in
            let codes = try urls.flatMap(ImageTools.readQR)
            return .message(codes.isEmpty ? "No QR code found" : codes.joined(separator: "\n"))
        },
        Tool("images-pdf", "Make PDF", symbol: "doc.richtext", [.image]) { urls, _ in .files([try ImageTools.toPDF(urls)]) },
        Tool("collage", "Collage", symbol: "square.grid.2x2", [.image], minFiles: 2,
             parameters: { urls in
                 let cols = Int(Double(urls.count).squareRoot().rounded(.up))
                 return [ToolParameter("columns", "Columns", .slider(min: 1, max: 6, step: 1, unit: ""), default: String(max(cols, 1)))]
             }) { urls, p in .files([try ImageTools.collage(urls, columns: Int(try p.double("columns")))]) },
        Tool("metadata", "Edit Metadata", symbol: "info.circle", [.image, .video, .audio, .pdf],
             parameters: { urls in
                 let current = urls.first.flatMap { try? Metadata.read($0) } ?? [:]
                 return Metadata.fields(for: urls.first.flatMap(Formats.category)).map {
                     ToolParameter($0.0, $0.1, .text(placeholder: $0.1), default: current[$0.0] ?? "")
                 }
             }) { urls, p in try eachFile(urls) { try Metadata.write($0, values: p) } },
        Tool("strip", "Remove Metadata", symbol: "xmark.bin", [.image, .video, .audio, .pdf]) { urls, _ in
            try eachFile(urls) { try Metadata.strip($0) }
        },
        Tool("trim", "Trim", symbol: "timeline.selection", media,
             parameters: { urls in [ToolParameter("start", "Start", .text(placeholder: "seconds or mm:ss"), default: "0"),
                                    ToolParameter("end", "End", .text(placeholder: "seconds or mm:ss"), default: fmt(duration(urls)))] }) { urls, p in
            let start = try parseTime(p.string("start")), end = try parseTime(p.string("end"))
            return try eachFile(urls) { try MediaTools.trim($0, start: start, end: end) }
        },
        Tool("crop-video", "Crop Video", symbol: "crop", [.video],
             parameters: { _ in [ToolParameter("aspect", "Aspect", .choice(["1:1", "4:5", "9:16", "16:9", "4:3", "Custom"]), default: "1:1"),
                                 ToolParameter("custom", "Custom (w:h:x:y)", .text(placeholder: "640:360:0:0"), default: "")] }) { urls, p in
            let spec = p.string("aspect") == "Custom" ? p.string("custom") : p.string("aspect")
            return try eachFile(urls) { try MediaTools.crop($0, aspect: spec) }
        },
        Tool("speed", "Change Speed", symbol: "gauge.with.dots.needle.67percent", media,
             parameters: { _ in [ToolParameter("factor", "Speed", .choice(["0.25x", "0.5x", "0.75x", "1.25x", "1.5x", "2x", "3x", "4x"]), default: "2x")] }) { urls, p in
            guard let factor = Double(p.string("factor").replacingOccurrences(of: "x", with: "")) else { throw ConversionError("Invalid speed") }
            return try eachFile(urls) { try MediaTools.speed($0, factor: factor) }
        },
        Tool("split", "Split", symbol: "scissors", media,
             parameters: { _ in [ToolParameter("mode", "Split", .choice(["Into equal parts", "Every N seconds"]), default: "Into equal parts"),
                                 ToolParameter("value", "Parts / seconds", .number(unit: ""), default: "2")] }) { urls, p in
            let value = try p.double("value")
            let byTime = p.string("mode") == "Every N seconds"
            return .files(try urls.flatMap { try MediaTools.split($0, parts: byTime ? nil : Int(value), every: byTime ? value : nil) })
        },
        Tool("join", "Join", symbol: "link", media, minFiles: 2) { urls, _ in .files([try MediaTools.join(urls)]) },
        Tool("snapshot", "Snapshot", symbol: "camera", [.video],
             parameters: { urls in [ToolParameter("time", "Time", .text(placeholder: "seconds or mm:ss"), default: fmt(duration(urls) / 2)),
                                    ToolParameter("format", "Format", .choice(["PNG", "JPG"]), default: "PNG")] }) { urls, p in
            let time = try parseTime(p.string("time")), format = p.string("format").lowercased()
            return try eachFile(urls) { try MediaTools.snapshot($0, at: time, format: format) }
        },
        Tool("mute", "Mute", symbol: "speaker.slash", [.video]) { urls, _ in try eachFile(urls, MediaTools.mute) },
        Tool("normalize", "Normalize", symbol: "waveform.badge.magnifyingglass", media,
             parameters: { _ in [ToolParameter("target", "Loudness", .choice(["-14 LUFS", "-16 LUFS", "-23 LUFS"]), default: "-16 LUFS")] }) { urls, p in
            let lufs = Double(p.string("target").split(separator: " ").first ?? "-16") ?? -16
            return try eachFile(urls) { try MediaTools.normalize($0, lufs: lufs) }
        },
        Tool("bleep", "Bleep", symbol: "speaker.wave.2.bubble", media,
             parameters: { _ in [ToolParameter("ranges", "Ranges", .text(placeholder: "1.5-2.0, 0:10-0:12"), default: "")] }) { urls, p in
            let ranges = try parseRanges(p.string("ranges"))
            return try eachFile(urls) { try MediaTools.bleep($0, ranges: ranges) }
        },
        Tool("channels", "Channels", symbol: "hifispeaker.2", media,
             parameters: { _ in [ToolParameter("mode", "Channels", .choice(MediaTools.channelModes), default: "Mono")] }) { urls, p in
            let mode = p.string("mode")
            return try eachFile(urls) { try MediaTools.channels($0, mode: mode) }
        },
        Tool("merge-pdf", "Merge PDFs", symbol: "doc.on.doc", [.pdf, .image], minFiles: 2) { urls, _ in .files([try PDFTools.merge(urls)]) },
        Tool("split-pdf", "Split PDF", symbol: "rectangle.split.3x1", [.pdf],
             parameters: { _ in [ToolParameter("ranges", "Page ranges (empty = every page)", .text(placeholder: "1-3, 4-6"), default: "")] }) { urls, p in
            .files(try urls.flatMap { try PDFTools.split($0, ranges: p.string("ranges")) })
        },
        Tool("reorganize-pdf", "Reorganize Pages", symbol: "square.grid.3x3.square", [.pdf], editor: .pdfPages,
             parameters: { urls in
                 let count = urls.first.map(PDFEngine.pageCount) ?? 0
                 return [ToolParameter("order", "Page order", .text(placeholder: "3, 1, 2:90"), default: (1...max(count, 1)).map(String.init).joined(separator: ", "))]
             }) { urls, p in
            try eachFile(urls) { url in try PDFTools.reorganize(url, pages: try pageEdits(p.string("order"), pageCount: PDFEngine.pageCount(url))) }
        },
        Tool("zip", "Zip", symbol: "archivebox", []) { urls, _ in .files([try zip(urls)]) },
    ]

    static func photoTool(_ id: String, _ name: String, _ symbol: String, _ mode: PhotoEditor.Mode) -> Tool {
        Tool(id, name, symbol: symbol, [.image], editor: .photo(mode),
             parameters: { _ in [ToolParameter("edit", "Edit", .text(placeholder: "JSON"), default: "{}")] }) { urls, p in
            let edit = try JSONDecoder().decode(PhotoEdit.self, from: Data(p.string("edit").utf8))
            return try eachFile(urls) { try PhotoEditor.apply(edit, to: $0) }
        }
    }

    /// "3, 1, 2:90" -> page edits (1-based input, optional ":degrees").
    public static func pageEdits(_ text: String, pageCount: Int) throws -> [PDFTools.PageEdit] {
        try text.split(separator: ",").map { item in
            let parts = item.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let n = parts.first.flatMap({ Int($0) }), (1...max(pageCount, 1)).contains(n) else {
                throw ConversionError("Invalid page \"\(item.trimmingCharacters(in: .whitespaces))\"")
            }
            return PDFTools.PageEdit(index: n - 1, rotation: parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
        }
    }

    static func zip(_ urls: [URL]) throws -> URL {
        if urls.count == 1 {
            let output = OutputNamer.unique(in: urls[0].deletingLastPathComponent(), base: urls[0].lastPathComponent, ext: "zip")
            try Archive.create(from: urls[0], to: output, ext: "zip")
            return output
        }
        let dir = urls[0].deletingLastPathComponent()
        let output = OutputNamer.unique(in: dir, base: "Archive", ext: "zip")
        try TempDir.with { staging in
            for url in urls { try FileManager.default.copyItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent)) }
            let names = urls.map(\.lastPathComponent)
            try Shell.run("/usr/bin/zip", ["-rXq", output.path] + names, cwd: staging)
        }
        return output
    }

    public static func applicable(to urls: [URL]) -> [Tool] { all.filter { $0.applies(to: urls) } }

    public static func tool(_ id: String) -> Tool? { all.first { $0.id == id } }
}
