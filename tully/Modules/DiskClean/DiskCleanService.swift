import Darwin
import Foundation
import os

nonisolated struct CleanTarget: Codable, Identifiable, Hashable, Sendable {
    enum Category: String, Codable, CaseIterable, Sendable {
        case caches, logs, developer, downloads, trash, other

        var title: String {
            switch self {
            case .caches:    "Caches"
            case .logs:      "Logs"
            case .developer: "Developer"
            case .downloads: "Downloads"
            case .trash:     "Trash"
            case .other:     "Other"
            }
        }

        var icon: String {
            switch self {
            case .caches:    "archivebox"
            case .logs:      "doc.text"
            case .developer: "hammer"
            case .downloads: "arrow.down.circle"
            case .trash:     "trash"
            case .other:     "folder"
            }
        }
    }

    var id = UUID()
    var name: String
    var paths: [String]
    var category: Category
    var isBuiltIn = false

    /// Items already in the Trash can't be moved there again; this target empties it instead.
    /// Only the built-in Trash target deletes; a custom target in the Trash category still goes to the Trash.
    var deletesPermanently: Bool { isBuiltIn && category == .trash }
}

nonisolated struct CleanItem: Identifiable, Hashable, Sendable {
    let url: URL
    let bytes: Int64
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

nonisolated struct TargetScan: Sendable {
    var items: [CleanItem] = []
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

/// Scans cleanup targets and moves what the user picks to the Trash (the Trash target is emptied).
@Observable
final class DiskCleanService {
    static let defaultBuiltInTargets: [CleanTarget] = [
        builtIn(1, "User Caches", ["~/Library/Caches/*"], .caches),
        builtIn(2, "Logs", ["~/Library/Logs/*"], .logs),
        builtIn(3, "Xcode Derived Data", ["~/Library/Developer/Xcode/DerivedData/*"], .developer),
        builtIn(4, "Installers in Downloads", ["~/Downloads/*.dmg", "~/Downloads/*.pkg"], .downloads),
        builtIn(5, "Trash", ["~/.Trash/*"], .trash),
    ]

    // stable ids so the saved selection survives relaunches
    private static func builtIn(_ n: Int, _ name: String, _ paths: [String], _ category: CleanTarget.Category) -> CleanTarget {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
        return CleanTarget(id: id, name: name, paths: paths, category: category, isBuiltIn: true)
    }

    static let customTargetsKey = "tully.diskClean.customTargets"
    static let deselectedKey = "tully.diskClean.deselected"

    let builtInTargets: [CleanTarget]
    private(set) var customTargets: [CleanTarget]
    private(set) var scans: [UUID: TargetScan] = [:]
    /// Locations that could not be read (usually need Full Disk Access).
    private(set) var unscannable: [String] = []
    private(set) var isScanning = false
    private(set) var isCleaning = false
    private(set) var lastResult: CleanResult?
    private(set) var deselected: Set<UUID>
    /// Single items the user unticked inside a selected target (not persisted; scans change).
    private(set) var excludedItems: Set<URL> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let logger = Logger(subsystem: "tully", category: "diskclean")

    nonisolated struct CleanResult: Equatable, Sendable {
        var freedBytes: Int64
        var itemCount: Int
        var failures: [String]
        /// Where trashed items ended up (lets the UI reveal them in the Trash).
        var trashedURLs: [URL] = []
    }

    init(defaults: UserDefaults = .standard, builtInTargets: [CleanTarget] = DiskCleanService.defaultBuiltInTargets) {
        self.defaults = defaults
        self.builtInTargets = builtInTargets
        customTargets = defaults.data(forKey: Self.customTargetsKey)
            .flatMap { try? JSONDecoder().decode([CleanTarget].self, from: $0) } ?? []
        if let stored = defaults.stringArray(forKey: Self.deselectedKey) {
            deselected = Set(stored.compactMap(UUID.init(uuidString:)))
        } else {
            // first run: opt out of the targets that hold the user's own files
            deselected = Set(builtInTargets.filter { $0.category == .downloads || $0.category == .trash }.map(\.id))
        }
    }

    var allTargets: [CleanTarget] { builtInTargets + customTargets }

    /// Items that will be cleaned: every item of a selected target that wasn't unticked.
    var selectedItems: [(target: CleanTarget, item: CleanItem)] {
        allTargets.filter(isSelected).flatMap { target in
            (scans[target.id]?.items ?? []).filter { !excludedItems.contains($0.url) }.map { (target, $0) }
        }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.item.bytes } }
    var selectionEmptiesTrash: Bool { selectedItems.contains { $0.target.deletesPermanently } }

    func isSelected(_ target: CleanTarget) -> Bool { !deselected.contains(target.id) }

    func setSelected(_ selected: Bool, for target: CleanTarget) {
        if selected { deselected.remove(target.id) } else { deselected.insert(target.id) }
        defaults.set(deselected.map(\.uuidString), forKey: Self.deselectedKey)
    }

    func isIncluded(_ item: CleanItem) -> Bool { !excludedItems.contains(item.url) }

    func setIncluded(_ included: Bool, item: CleanItem) {
        if included { excludedItems.remove(item.url) } else { excludedItems.insert(item.url) }
    }

    // MARK: - Custom targets

    func addCustomTarget(_ target: CleanTarget) {
        customTargets.append(target)
        saveCustomTargets()
    }

    func removeCustomTarget(id: UUID) {
        customTargets.removeAll { $0.id == id }
        scans[id] = nil
        saveCustomTargets()
    }

    // MARK: - Scan & clean

    func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        let targets = allTargets
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.scan(targets)
            await self?.finishScan(scans: result.scans, unscannable: result.unscannable)
        }
    }

    /// Scans synchronously off the main actor. Internal for tests.
    nonisolated static func scan(_ targets: [CleanTarget]) -> (scans: [UUID: TargetScan], unscannable: [String]) {
        var scans: [UUID: TargetScan] = [:]
        var unscannable: [String] = []
        for target in targets {
            var scan = TargetScan()
            for pattern in target.paths where DiskCleanPathPolicy.check(pattern) == .allowed {
                guard isReadable(pattern: pattern) else {
                    unscannable.append(pattern)
                    continue
                }
                scan.items += expand(pattern).map { CleanItem(url: $0, bytes: DiskScanService.allocatedSize(of: $0)) }
            }
            scan.items.sort { $0.bytes > $1.bytes }
            scans[target.id] = scan
        }
        return (scans, unscannable)
    }

    private func finishScan(scans: [UUID: TargetScan], unscannable: [String]) {
        self.scans = scans
        self.unscannable = unscannable
        excludedItems = excludedItems.filter { url in scans.values.contains { $0.items.contains { $0.url == url } } }
        isScanning = false
    }

    /// Moves the selected items to the Trash (Trash items are deleted), then rescans.
    func cleanSelected(completion: ((CleanResult) -> Void)? = nil) {
        guard !isScanning, !isCleaning else { return }
        let work = selectedItems.map { (url: $0.item.url, bytes: $0.item.bytes, permanent: $0.target.deletesPermanently) }
        isCleaning = true
        lastResult = nil
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.clean(work)
            await self?.finishClean(result, completion: completion)
        }
    }

    private func finishClean(_ result: CleanResult, completion: ((CleanResult) -> Void)?) {
        result.failures.forEach { logger.error("Disk clean failed for \($0, privacy: .private)") }
        lastResult = result
        isCleaning = false
        completion?(result)
        scan()
    }

    nonisolated static func clean(_ work: [(url: URL, bytes: Int64, permanent: Bool)],
                                  fileManager: FileManager = .default) -> CleanResult {
        var result = CleanResult(freedBytes: 0, itemCount: 0, failures: [])
        for entry in work {
            // re-check against the real location so symlinked parents can't escape the policy
            guard !isSelfOrParentEntry(entry.url),
                  let resolved = resolvedPath(of: entry.url), DiskCleanPathPolicy.check(resolved) == .allowed else {
                result.failures.append(entry.url.path)
                continue
            }
            do {
                if entry.permanent {
                    try fileManager.removeItem(at: entry.url) // removes a symlink itself, never its target
                } else {
                    var trashed: NSURL?
                    try fileManager.trashItem(at: entry.url, resultingItemURL: &trashed)
                    if let trashed { result.trashedURLs.append(trashed as URL) }
                }
                result.freedBytes += entry.bytes
                result.itemCount += 1
            } catch {
                result.failures.append(entry.url.path)
            }
        }
        return result
    }

    // MARK: - Private

    nonisolated static func isSelfOrParentEntry(_ url: URL) -> Bool {
        let last = (url.path as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || url.path.hasSuffix("/.") || url.path.hasSuffix("/..")
    }

    private nonisolated static func resolvedPath(of url: URL) -> String? {
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else { return nil }
        defer { free(parent) }
        return String(cString: parent) + "/" + url.lastPathComponent
    }

    nonisolated static func expand(_ pattern: String) -> [URL] {
        var matches = glob_t()
        defer { globfree(&matches) }
        guard glob(pattern, GLOB_TILDE, nil, &matches) == 0 else { return [] }
        return (0..<Int(matches.gl_pathc)).compactMap { index in
            matches.gl_pathv[index].map { URL(fileURLWithPath: String(cString: $0)) }
        }
        // "dir/.*" also matches "dir/." and "dir/..", which would clean the folder itself
        .filter { !isSelfOrParentEntry($0) }
    }

    /// The deepest wildcard-free directory of the pattern must be listable.
    private nonisolated static func isReadable(pattern: String) -> Bool {
        let expanded = (pattern as NSString).expandingTildeInPath
        var directory = expanded.contains("*") ? (expanded as NSString).deletingLastPathComponent : expanded
        while directory.contains("*") { directory = (directory as NSString).deletingLastPathComponent }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) else { return true } // nothing to clean
        guard isDirectory.boolValue else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: directory)) != nil
    }

    private func saveCustomTargets() {
        guard let data = try? JSONEncoder().encode(customTargets) else { return }
        defaults.set(data, forKey: Self.customTargetsKey)
    }
}
