import Foundation

/// ZIP/TAR/GZIP via ditto and bsdtar. bsdtar (libarchive) also reads RAR.
public enum Archive {
    public static func extract(_ input: URL, to dir: URL) throws {
        switch canonicalExtension(of: input) {
        case "zip": try Zip.extract(input, to: dir)
        case "gz":
            let out = dir.appendingPathComponent(OutputNamer.baseName(of: input))
            try Shell.run("/bin/sh", ["-c", "/usr/bin/gzip -dc \"$0\" > \"$1\"", input.path, out.path])
        default: try Shell.run("/usr/bin/tar", ["-xf", input.path, "-C", dir.path])
        }
    }

    /// Archives `item` (file or folder) keeping its name as the top-level entry.
    public static func create(from item: URL, to output: URL, ext: String) throws {
        let parent = item.deletingLastPathComponent()
        switch ext {
        case "zip":
            // --keepParent on a plain file would also store its parent folder; only folders need it.
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc"] + (isDir == true ? ["--keepParent"] : []) + [item.path, output.path])
        case "tar": try Shell.run("/usr/bin/tar", ["-cf", output.path, "-C", parent.path, item.lastPathComponent])
        case "tar.gz": try Shell.run("/usr/bin/tar", ["-czf", output.path, "-C", parent.path, item.lastPathComponent])
        default: throw ConversionError("Unsupported archive output \(ext)")
        }
    }

    /// Repacks an archive as another format, or extracts it to a folder ("folder").
    public static func convert(_ input: URL, to ext: String, output: URL) throws {
        if ext == "folder" {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            return try extract(input, to: output)
        }
        try TempDir.with { dir in
            let root = dir.appendingPathComponent(OutputNamer.baseName(of: input))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try extract(input, to: root)
            // Single top-level folder inside? Archive that instead of double-nesting.
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { !$0.lastPathComponent.hasPrefix(".") && $0.lastPathComponent != "__MACOSX" }
            let isDir = (try? entries.first?.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try create(from: entries.count == 1 && isDir == true ? entries[0] : root, to: output, ext: ext)
        }
    }

    public static func list(_ input: URL) throws -> [String] {
        try Shell.run("/usr/bin/tar", ["-tf", input.path]).split(separator: "\n").map(String.init)
    }
}
