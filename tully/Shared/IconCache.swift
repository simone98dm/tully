import AppKit

/// File icons are slow to fetch and views re-render every sample, so keep them.
enum IconCache {
    private static var icons: [String: NSImage] = [:]
    private static let limit = 300

    static func icon(forFile path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        if icons.count >= limit { icons.removeAll() } // ponytail: crude cap; LRU if apps ever have hundreds of helpers
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
