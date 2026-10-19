import Foundation

/// ffmpeg-backed video/audio tools. All write new files beside the input.
public enum MediaTools {
    static func ext(_ url: URL) -> String { canonicalExtension(of: url) }
    static func out(_ url: URL, _ suffix: String, ext: String? = nil) -> URL {
        OutputNamer.output(for: url, ext: ext ?? canonicalExtension(of: url), suffix: suffix)
    }
    static func seconds(_ t: Double) -> String { String(format: "%.3f", t) }

    public static func trim(_ url: URL, start: Double, end: Double) throws -> URL {
        guard end > start else { throw ConversionError("End must be after start") }
        let output = out(url, " trimmed")
        try MediaEngine.encode([url], output: output, ext: ext(url), inputArgs: ["-ss", seconds(start)],
                               extra: ["-t", seconds(end - start), "-map_metadata", "0"])
        return output
    }

    /// `aspect` like "16:9", or "w:h:x:y" in pixels for a custom crop. Centered for aspect crops.
    public static func crop(_ url: URL, aspect: String) throws -> URL {
        let parts = aspect.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let filter: String
        switch parts.count {
        case 2 where parts[0] > 0 && parts[1] > 0:
            let r = parts[0] / parts[1]
            filter = "crop='if(gt(iw/ih,\(r)),ih*\(r),iw)':'if(gt(iw/ih,\(r)),ih,iw/\(r))'"
        case 4: filter = "crop=\(Int(parts[0])):\(Int(parts[1])):\(Int(parts[2])):\(Int(parts[3]))"
        default: throw ConversionError("Crop must be an aspect like 16:9 or w:h:x:y")
        }
        let output = out(url, " cropped")
        try MediaEngine.encode([url], output: output, ext: ext(url), videoFilters: [filter])
        return output
    }

    /// atempo accepts 0.5...2 per instance, so chain it for larger factors.
    static func atempoChain(_ speed: Double) -> String {
        var remaining = speed, parts: [String] = []
        while remaining > 2 { parts.append("atempo=2.0"); remaining /= 2 }
        while remaining < 0.5 { parts.append("atempo=0.5"); remaining /= 0.5 }
        parts.append("atempo=\(remaining)")
        return parts.joined(separator: ",")
    }

    public static func speed(_ url: URL, factor: Double) throws -> URL {
        guard factor > 0 else { throw ConversionError("Speed must be positive") }
        let info = try MediaEngine.probe(url)
        let output = out(url, " \(factor.formatted())x")
        try MediaEngine.encode([url], output: output, ext: ext(url),
                               videoFilters: info.hasVideo ? ["setpts=PTS/\(factor)"] : [],
                               audioFilters: info.hasAudio ? [atempoChain(factor)] : [])
        return output
    }

    /// Splits into `parts` equal pieces, or every `every` seconds when given.
    public static func split(_ url: URL, parts: Int? = nil, every: Double? = nil) throws -> [URL] {
        let duration = try MediaEngine.probe(url).duration
        guard duration > 0 else { throw ConversionError("Can't read duration") }
        let length = every ?? duration / Double(max(parts ?? 2, 1))
        guard length > 0.05 else { throw ConversionError("Segments are too short") }
        var outputs: [URL] = [], start = 0.0, index = 1
        while start < duration - 0.05 {
            let output = out(url, " part \(index)")
            try MediaEngine.encode([url], output: output, ext: ext(url), inputArgs: ["-ss", seconds(start)],
                                   extra: ["-t", seconds(min(length, duration - start))])
            outputs.append(output)
            start += length; index += 1
        }
        return outputs
    }

    /// Concatenates videos (re-encoded, scaled to the first one's size) or audio files.
    public static func join(_ urls: [URL]) throws -> URL {
        guard urls.count >= 2 else { throw ConversionError("Choose at least two files to join") }
        let infos = try urls.map(MediaEngine.probe)
        let output = OutputNamer.output(for: urls[0], ext: ext(urls[0]), suffix: " joined")
        let isVideo = infos[0].hasVideo
        var chains: [String] = [], inputs = ""
        for (i, info) in infos.enumerated() {
            if isVideo {
                let w = infos[0].width / 2 * 2, h = infos[0].height / 2 * 2
                chains.append("[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(i)]")
                chains.append(info.hasAudio ? "[\(i):a]aresample=44100,aformat=channel_layouts=stereo[a\(i)]"
                                            : "anullsrc=r=44100:cl=stereo,atrim=0:\(info.duration)[a\(i)]")
                inputs += "[v\(i)][a\(i)]"
            } else {
                chains.append("[\(i):a]aresample=44100,aformat=channel_layouts=stereo[a\(i)]")
                inputs += "[a\(i)]"
            }
        }
        let concat = "\(inputs)concat=n=\(urls.count):v=\(isVideo ? 1 : 0):a=1" + (isVideo ? "[v][a]" : "[a]")
        let maps = isVideo ? ["-map", "[v]", "-map", "[a]"] : ["-map", "[a]"]
        try MediaEngine.encode(urls, output: output, ext: ext(urls[0]),
                               filterComplex: (chains + [concat]).joined(separator: ";"), extra: maps)
        return output
    }

    public static func snapshot(_ url: URL, at time: Double, format: String = "png") throws -> URL {
        let output = out(url, " frame", ext: format)
        try Shell.ffmpeg(["-ss", seconds(time), "-i", url.path, "-frames:v", "1", "-update", "1", output.path])
        guard FileManager.default.fileExists(atPath: output.path) else { throw ConversionError("No frame at that time") }
        return output
    }

    public static func mute(_ url: URL) throws -> URL {
        let output = out(url, " muted")
        try Shell.ffmpeg(["-i", url.path, "-map", "0:v", "-c:v", "copy", "-an", output.path])
        return output
    }

    public static func rotate(_ url: URL, degrees: Int, flip: String? = nil) throws -> URL {
        var filters: [String] = []
        switch ((degrees % 360) + 360) % 360 {
        case 90: filters.append("transpose=1")
        case 180: filters.append("transpose=1,transpose=1")
        case 270: filters.append("transpose=2")
        default: break
        }
        if flip == "Horizontal" { filters.append("hflip") }
        if flip == "Vertical" { filters.append("vflip") }
        let output = out(url, flip != nil ? " flipped" : " rotated")
        try MediaEngine.encode([url], output: output, ext: ext(url), videoFilters: filters)
        return output
    }

    /// EBU R128 loudness normalization.
    public static func normalize(_ url: URL, lufs: Double = -16) throws -> URL {
        let output = out(url, " normalized")
        try MediaEngine.encode([url], output: output, ext: ext(url),
                               audioFilters: ["loudnorm=I=\(lufs):TP=-1.5:LRA=11", "aresample=48000"])
        return output
    }

    /// Silences each range and lays a 1 kHz tone over it.
    public static func bleep(_ url: URL, ranges: [ClosedRange<Double>]) throws -> URL {
        guard !ranges.isEmpty else { throw ConversionError("Add at least one range to bleep") }
        let info = try MediaEngine.probe(url)
        guard info.hasAudio else { throw ConversionError("File has no audio") }
        let when = ranges.map { "between(t,\($0.lowerBound),\($0.upperBound))" }.joined(separator: "+")
        let graph = """
        [0:a]volume=0:enable='\(when)'[muted];\
        sine=frequency=1000:sample_rate=48000:duration=\(max(info.duration, 0.1)),volume=0.3,volume=0:enable='not(\(when))'[tone];\
        [muted][tone]amix=inputs=2:duration=first:normalize=0[a]
        """
        let output = out(url, " bleeped")
        let maps = info.hasVideo ? ["-map", "0:v", "-map", "[a]"] : ["-map", "[a]"]
        if info.hasVideo {
            try Shell.ffmpeg(["-i", url.path, "-filter_complex", graph] + maps + ["-c:v", "copy"] + MediaEngine.audioCodec(ext(url)) + [output.path])
        } else {
            try MediaEngine.encode([url], output: output, ext: ext(url), filterComplex: graph, extra: maps)
        }
        return output
    }

    public static let channelModes = ["Mono", "Stereo", "Swap Left/Right", "Left Only", "Right Only"]

    public static func channels(_ url: URL, mode: String) throws -> URL {
        let filter: String
        switch mode {
        case "Mono": filter = "aformat=channel_layouts=mono"
        case "Stereo": filter = "aformat=channel_layouts=stereo"
        case "Swap Left/Right": filter = "pan=stereo|c0=c1|c1=c0"
        case "Left Only": filter = "pan=stereo|c0=c0|c1=c0"
        case "Right Only": filter = "pan=stereo|c0=c1|c1=c1"
        default: throw ConversionError("Unknown channel mode \(mode)")
        }
        let output = out(url, " \(mode.lowercased().replacingOccurrences(of: "/", with: "-"))")
        try MediaEngine.encode([url], output: output, ext: ext(url), audioFilters: [filter])
        return output
    }
}
