import Foundation

public struct ShellError: LocalizedError {
    public let command: String
    public let status: Int32
    public let output: String
    public var errorDescription: String? {
        let tail = output.split(separator: "\n").suffix(4).joined(separator: "\n")
        return "\(command) failed (\(status)): \(tail)"
    }
}

public struct MissingToolError: LocalizedError {
    public let tool: String
    public var errorDescription: String? {
        "\(tool) is required for this conversion. Install it with: brew install \(tool == "cwebp" ? "webp" : tool)"
    }
}

public enum Shell {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"]

    /// Finds an executable: bundled `Resources/bin` first, then common install locations.
    public static func which(_ name: String) -> String? {
        var dirs: [String] = []
        if let res = Bundle.main.resourceURL?.appendingPathComponent("bin").path { dirs.append(res) }
        dirs += searchPaths
        return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func require(_ name: String) throws -> String {
        guard let path = which(name) else { throw MissingToolError(tool: name) }
        return path
    }

    /// Runs a process to completion; throws with combined output on non-zero exit.
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], cwd: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ShellError(command: (executable as NSString).lastPathComponent, status: process.terminationStatus, output: output)
        }
        return output
    }

    public static func ffmpeg(_ arguments: [String]) throws {
        try run(try require("ffmpeg"), ["-hide_banner", "-loglevel", "error", "-y"] + arguments)
    }

    public static func ffprobe(_ arguments: [String]) throws -> String {
        try run(try require("ffprobe"), ["-v", "error"] + arguments)
    }

    public static func osascript(_ script: String) throws {
        try run("/usr/bin/osascript", ["-e", script])
    }
}

/// ImageIO and Quartz PDF contexts don't truncate existing files, so clear the target before writing.
func clearOutput(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

public enum TempDir {
    public static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kumquat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs `body` with a fresh temp dir that is removed afterwards.
    public static func with<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = try make()
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }
}
