import Foundation

/// Guards which paths Disk Clean may ever delete (rules from One Menu's custom-target docs).
nonisolated enum DiskCleanPathPolicy {
    /// Never targetable, nor anything below them.
    static let blockedRoots = ["/System", "/bin", "/sbin", "/usr", "/etc", "/var", "/private"]
    /// Targetable only at depth ≥ 4 (e.g. /Users/me/Library/Caches).
    static let restrictedRoots = ["/Library", "/Applications", "/Users", "/Volumes"]
    static let minimumRestrictedDepth = 4

    enum Verdict: Equatable {
        case allowed
        case rejected(String)
    }

    /// `path` may use `~` and `*`; `**` is rejected.
    static func check(_ path: String) -> Verdict {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .rejected("Path is empty") }
        guard !trimmed.contains("**") else { return .rejected("Recursive wildcard ** is not supported") }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return .rejected("Use an absolute path or start with ~") }

        guard !expanded.split(separator: "/").contains("..") else { return .rejected("Path must not contain ..") }
        let components = (expanded as NSString).standardizingPath
            .split(separator: "/").map(String.init)
        guard !components.isEmpty else { return .rejected("The root folder cannot be cleaned") }

        let normalized = "/" + components.joined(separator: "/")
        if let root = blockedRoots.first(where: { normalized == $0 || normalized.hasPrefix($0 + "/") }) {
            return .rejected("\(root) is protected")
        }
        if let root = restrictedRoots.first(where: { normalized == $0 || normalized.hasPrefix($0 + "/") }),
           components.count < minimumRestrictedDepth {
            return .rejected("Paths inside \(root) must be at least \(minimumRestrictedDepth) levels deep")
        }
        return .allowed
    }
}
