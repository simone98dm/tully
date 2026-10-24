import AppKit

/// The actions wheel. AirDrop and Float need UI and are performed by the app.
public enum FileAction: String, CaseIterable, Sendable {
    // Declaration order is wheel order, clockwise from the top: clipboard first, "open in" apps last.
    case copy, copyPath, move, float, airDrop, terminal, iTerm, vsCode

    public var title: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .float: return "Float"
        case .copy: return "Copy"
        case .move: return "Move"
        case .copyPath: return "Copy Path"
        case .terminal: return "Terminal"
        case .iTerm: return "Open folder in iTerm2"
        case .vsCode: return "Open in VS Code"
        }
    }

    /// Title for these files: Terminal on a folder reads "Open folder in Terminal".
    public func title(for urls: [URL]) -> String {
        self == .terminal && FileActions.areFolders(urls) ? "Open folder in Terminal" : title
    }

    public var symbol: String {
        switch self {
        case .airDrop: return "airplayaudio"
        case .float: return "pip"
        case .copy: return "doc.on.clipboard"
        case .move: return "folder"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        case .iTerm: return "apple.terminal.on.rectangle"
        case .vsCode: return "chevron.left.forwardslash.chevron.right"
        }
    }

    /// The app an "open in" action needs, by bundle identifier.
    public var requiredAppBundleID: String? {
        switch self {
        case .iTerm: return "com.googlecode.iterm2"
        case .vsCode: return "com.microsoft.VSCode"
        default: return nil
        }
    }

    /// "Open in" entries also shown on the Tools wheel: Terminal and iTerm2 for folders, VS Code for code files.
    public static func openIn(for urls: [URL], isInstalled: (String) -> Bool = FileActions.isInstalled) -> [FileAction] {
        applicable(to: urls, isInstalled: isInstalled).filter { action in
            action == .iTerm || action == .vsCode || (action == .terminal && FileActions.areFolders(urls))
        }
    }

    /// Actions offered for `urls`. iTerm2 only for folders, VS Code only for code files,
    /// and only when the app is installed.
    public static func applicable(to urls: [URL], isInstalled: (String) -> Bool = FileActions.isInstalled) -> [FileAction] {
        allCases.filter { action in
            if let bundleID = action.requiredAppBundleID, !isInstalled(bundleID) { return false }
            switch action {
            case .iTerm: return FileActions.areFolders(urls)
            case .vsCode: return FileActions.areCodeFiles(urls)
            default: return true
            }
        }
    }
}

public enum FileActions {
    /// Puts the files themselves on the pasteboard (paste in Finder, Mail, Messages...).
    public static func copyFiles(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    public static func copyPaths(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    /// Moves into `folder`, renaming on collision. Returns the new locations.
    public static func move(_ urls: [URL], to folder: URL) throws -> [URL] {
        try urls.map { url in
            let target = OutputNamer.unique(in: folder, base: url.deletingPathExtension().lastPathComponent,
                                            ext: url.pathExtension.isEmpty ? nil : url.pathExtension)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        }
    }

    /// Opens Terminal in the file's folder (or the folder itself).
    public static func terminalDirectory(for url: URL) -> URL {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? url : url.deletingLastPathComponent()
    }

    public static func openTerminal(at url: URL) throws {
        try Shell.run("/usr/bin/open", ["-a", "Terminal", terminalDirectory(for: url).path])
    }

    /// Opens the files with the app for an "open in" action (iTerm2 gets the folder, VS Code the files).
    public static func open(_ urls: [URL], for action: FileAction) throws {
        guard let bundleID = action.requiredAppBundleID else { return }
        let targets = action == .iTerm ? urls.map(terminalDirectory(for:)) : urls
        try Shell.run("/usr/bin/open", ["-b", bundleID] + targets.map(\.path))
    }

    public static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    public static func areFolders(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? $0.hasDirectoryPath }
    }

    /// Source code and config files developers open in an editor.
    public static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "cs", "java", "kt", "kts", "scala", "go", "rs", "zig",
        "py", "rb", "php", "pl", "lua", "r", "dart", "ex", "exs", "erl", "hs", "clj", "fs",
        "js", "mjs", "cjs", "ts", "tsx", "jsx", "vue", "svelte", "astro",
        "html", "htm", "css", "scss", "sass", "less",
        "json", "jsonc", "yaml", "yml", "toml", "xml", "plist", "ini", "env", "conf", "properties", "gradle",
        "sh", "bash", "zsh", "fish", "ps1", "bat", "sql", "graphql", "gql", "proto", "tf", "dockerfile",
        "md", "mdx", "rst", "tex", "lock", "gitignore", "editorconfig",
    ]
    public static let codeFileNames: Set<String> = ["Dockerfile", "Makefile", "Podfile", "Gemfile", "Rakefile", "Procfile", "Brewfile"]

    public static func isCodeFile(_ url: URL) -> Bool {
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return false }
        let name = url.lastPathComponent
        if codeFileNames.contains(name) { return true }
        // dotfiles like .gitignore or .env have no extension, only a name
        let ext = url.pathExtension.isEmpty && name.hasPrefix(".") ? String(name.dropFirst()) : url.pathExtension
        return codeExtensions.contains(ext.lowercased())
    }

    public static func areCodeFiles(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy(isCodeFile)
    }
}
