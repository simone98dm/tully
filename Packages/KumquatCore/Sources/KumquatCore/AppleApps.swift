import AppKit

public enum AppleApp: String, Sendable {
    case pages = "Pages", keynote = "Keynote", numbers = "Numbers"
    var bundleID: String { "com.apple.iWork.\(rawValue)" }
}

/// Proprietary iWork formats (and legacy .ppt/.xls) have no public codec, so we drive the Apple apps when installed.
public enum AppleApps {
    public static func isInstalled(_ app: AppleApp) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) != nil
    }

    static func requireInstalled(_ app: AppleApp) throws {
        guard isInstalled(app) else {
            throw ConversionError("\(app.rawValue) is required for this format. Install it free from the Mac App Store.")
        }
    }

    static func quoted(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// `format`: an iWork export format, e.g. "PDF", "Microsoft Word", "Microsoft Excel", "CSV", "Microsoft PowerPoint".
    public static func export(_ input: URL, to output: URL, app: AppleApp, format: String) throws {
        try requireInstalled(app)
        try Shell.osascript("""
        tell application "\(app.rawValue)"
            set d to open (POSIX file \(quoted(input.path)))
            export d to (POSIX file \(quoted(output.path))) as \(format)
            close d saving no
        end tell
        """)
    }

    /// Opens a foreign document and saves it in the app's own format (.pages/.key/.numbers).
    public static func saveNative(_ input: URL, to output: URL, app: AppleApp) throws {
        try requireInstalled(app)
        try Shell.osascript("""
        tell application "\(app.rawValue)"
            set d to open (POSIX file \(quoted(input.path)))
            save d in (POSIX file \(quoted(output.path)))
            close d saving no
        end tell
        """)
    }
}
