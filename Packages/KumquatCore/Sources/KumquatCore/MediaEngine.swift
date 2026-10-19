import Foundation

public struct MediaInfo: Sendable {
    public let duration: Double
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let width: Int
    public let height: Int
    public let tags: [String: String]
}

/// Video and audio via ffmpeg.
public enum MediaEngine {
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]
    static let evenDims = "scale=trunc(iw/2)*2:trunc(ih/2)*2"

    nonisolated(unsafe) private static var encoderCache: String?
    static func hasEncoder(_ name: String) -> Bool {
        if encoderCache == nil, let ffmpeg = Shell.which("ffmpeg") {
            encoderCache = (try? Shell.run(ffmpeg, ["-hide_banner", "-encoders"])) ?? ""
        }
        return encoderCache?.contains(" \(name) ") ?? false
    }

    public static func probe(_ url: URL) throws -> MediaInfo {
        let json = try Shell.ffprobe(["-show_entries", "format=duration:format_tags:stream=codec_type,width,height",
                                      "-of", "json", url.path])
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] ?? [:]
        let format = root["format"] as? [String: Any] ?? [:]
        let streams = root["streams"] as? [[String: Any]] ?? []
        let video = streams.first { $0["codec_type"] as? String == "video" }
        return MediaInfo(
            duration: Double(format["duration"] as? String ?? "") ?? 0,
            hasVideo: video != nil,
            hasAudio: streams.contains { $0["codec_type"] as? String == "audio" },
            width: video?["width"] as? Int ?? 0,
            height: video?["height"] as? Int ?? 0,
            tags: (format["tags"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String })
    }

    static func h264(_ rate: [String]?) -> [String] {
        hasEncoder("libx264")
            ? ["-c:v", "libx264", "-preset", "medium"] + (rate ?? ["-crf", "23"]) + ["-pix_fmt", "yuv420p"]
            : ["-c:v", "h264_videotoolbox"] + (rate ?? ["-b:v", "5M"]) + ["-pix_fmt", "yuv420p"]
    }

    /// Audio codec arguments for an output extension. `bitrate` swaps quality mode for a fixed rate.
    static func audioCodec(_ ext: String, bitrate: String? = nil) -> [String] {
        let codec = audioCodecDefaults(ext)
        guard let bitrate, codec.count >= 2, !["pcm_s16le", "pcm_s16be", "flac"].contains(codec[1]) else { return codec }
        return Array(codec.prefix(2)) + ["-b:a", bitrate] + (codec.contains("-ac") ? ["-strict", "-2", "-ac", "2"] : [])
    }

    static func audioCodecDefaults(_ ext: String) -> [String] {
        switch ext {
        case "mp3": return ["-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a", "mp4", "mov", "mkv": return ["-c:a", "aac", "-b:a", "192k"]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "flac": return ["-c:a", "flac"]
        case "ogg": return hasEncoder("libvorbis") ? ["-c:a", "libvorbis", "-q:a", "5"]
                                                   : ["-c:a", "vorbis", "-strict", "-2", "-ac", "2"]
        case "opus", "webm": return ["-c:a", "libopus", "-b:a", "128k"]
        case "aiff": return ["-c:a", "pcm_s16be"]
        case "wma", "wmv": return ["-c:a", "wmav2", "-b:a", "192k"]
        case "avi": return ["-c:a", "libmp3lame", "-q:a", "3"]
        default: return []
        }
    }

    /// Video codec arguments (without filters). `bitrate` overrides the default quality mode.
    static func videoCodec(_ ext: String, bitrate: String? = nil) -> [String] {
        let rate = bitrate.map { ["-b:v", $0] }
        switch ext {
        case "mp4": return h264(rate) + ["-movflags", "+faststart"]
        case "mov", "mkv": return h264(rate)
        case "webm": return ["-c:v", "libvpx-vp9"] + (rate ?? ["-crf", "32", "-b:v", "0"])
            + ["-row-mt", "1", "-deadline", "good", "-cpu-used", "4", "-pix_fmt", "yuv420p"]
        case "avi": return ["-c:v", "mpeg4"] + (rate ?? ["-q:v", "4"])
        case "wmv": return ["-c:v", "wmv2"] + (rate ?? ["-b:v", "3M"])
        default: return []
        }
    }

    /// Single entry point for every ffmpeg encode: conversions and tools build on it.
    public static func encode(_ inputs: [URL], output: URL, ext: String,
                              inputArgs: [String] = [], videoFilters: [String] = [], audioFilters: [String] = [],
                              filterComplex: String? = nil, extra: [String] = [], videoBitrate: String? = nil,
                              audioBitrate: String? = nil) throws {
        var args = inputArgs
        for input in inputs { args += ["-i", input.path] }
        if let filterComplex { args += ["-filter_complex", filterComplex] }
        if ext == "gif" {
            let chain = (videoFilters + ["fps=12", "scale='min(640,iw)':-1:flags=lanczos"]).joined(separator: ",")
            args += ["-vf", "\(chain),split[a][b];[a]palettegen[p];[b][p]paletteuse", "-an", "-loop", "0"]
        } else if videoExts.contains(ext) {
            if filterComplex == nil { args += ["-vf", (videoFilters + [evenDims]).joined(separator: ",")] }
            args += videoCodec(ext, bitrate: videoBitrate) + audioCodec(ext, bitrate: audioBitrate)
            if !audioFilters.isEmpty, filterComplex == nil { args += ["-af", audioFilters.joined(separator: ",")] }
        } else {
            args += ["-vn"] + audioCodec(ext, bitrate: audioBitrate)
            if !audioFilters.isEmpty { args += ["-af", audioFilters.joined(separator: ",")] }
        }
        try Shell.ffmpeg(args + extra + [output.path])
    }

    public static func convert(_ input: URL, to ext: String, output: URL) throws {
        try encode([input], output: output, ext: ext, extra: ["-map_metadata", "0"])
    }
}
