import Foundation

public struct Cue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
}

public enum Subtitles {
    public static func parse(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]),
                  let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]) else { return nil }
            return Cue(start: start, end: end, text: lines[(timing + 1)...].joined(separator: "\n"))
        }
    }

    /// Parses `HH:MM:SS,mmm`, `HH:MM:SS.mmm` or `MM:SS.mmm`.
    public static func time(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count else { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }

    static func stamp(_ t: Double, separator: String) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, separator, ms % 1000)
    }

    public static func srt(_ cues: [Cue]) -> String {
        cues.enumerated().map { "\($0 + 1)\n\(stamp($1.start, separator: ",")) --> \(stamp($1.end, separator: ","))\n\($1.text)\n" }
            .joined(separator: "\n")
    }

    public static func vtt(_ cues: [Cue]) -> String {
        "WEBVTT\n\n" + cues.map { "\(stamp($0.start, separator: ".")) --> \(stamp($0.end, separator: "."))\n\($0.text)\n" }
            .joined(separator: "\n")
    }

    public static func plain(_ cues: [Cue]) -> String {
        cues.map { $0.text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }.joined(separator: "\n") + "\n"
    }

    public static func convert(_ input: URL, to ext: String, output: URL) throws {
        let cues = parse(try RichText.readPlainText(input))
        guard !cues.isEmpty else { throw ConversionError("No subtitle cues found") }
        let text = ext == "srt" ? srt(cues) : ext == "vtt" ? vtt(cues) : plain(cues)
        try text.write(to: output, atomically: true, encoding: .utf8)
    }
}
