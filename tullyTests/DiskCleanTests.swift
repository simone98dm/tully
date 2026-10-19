import Foundation
import Testing
@testable import tully

struct DiskCleanPathPolicyTests {
    @Test(arguments: [
        ("/", false),
        ("/System/Library/Caches", false),
        ("/private/var/folders/x", false),
        ("/usr/local/lib/foo", false),
        ("/Users/username/Documents", false),     // 3 levels
        ("/Users/username/Library/Caches", true), // 4 levels
        ("/Library/Caches/SomeApp/Logs", true),
        ("/Library/Caches", false),
        ("/Applications/Foo.app", false),
        ("~/Downloads/*.tmp", true),
        ("~/Documents", false),
        ("~/**/cache", false),
        ("~/Library/Caches/../../../..", false),
        ("relative/path", false),
        ("/Systemic/thing/a/b", true),            // prefix match is per component
        ("   ", false),
    ])
    func policy(path: String, allowed: Bool) {
        #expect((DiskCleanPathPolicy.check(path) == .allowed) == allowed, "\(path)")
    }
}

/// Uses a scratch folder inside ~/Library/Caches: temp dirs live under /private, which the policy blocks.
@MainActor
final class DiskCleanServiceTests {
    let root: URL

    init() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/com.simone98dm.tully.tests/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeFile(_ name: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func target(_ pattern: String, category: CleanTarget.Category = .caches) -> CleanTarget {
        CleanTarget(name: "Test", paths: [root.path + "/" + pattern], category: category)
    }

    @Test func scanExpandsGlobAndSortsBySize() throws {
        _ = try makeFile("small.tmp", bytes: 10)
        _ = try makeFile("big.tmp", bytes: 200_000)
        _ = try makeFile("keep.txt", bytes: 50_000)
        let t = target("*.tmp")
        let scan = DiskCleanService.scan([t]).scans[t.id]
        #expect(scan?.items.map(\.name) == ["big.tmp", "small.tmp"])
        #expect((scan?.bytes ?? 0) >= 200_000)
    }

    @Test func cleanMovesOnlySelectedItemsToTrash() async throws {
        let a = try makeFile("a.tmp", bytes: 4096)
        let b = try makeFile("b.tmp", bytes: 4096)
        let service = DiskCleanService(defaults: makeDefaults(), builtInTargets: [])
        let t = target("*.tmp")
        service.addCustomTarget(t)
        try await scanAndWait(service)
        service.setIncluded(false, item: CleanItem(url: b, bytes: 0))
        #expect(service.selectedItems.map(\.item.url.lastPathComponent) == ["a.tmp"])

        let result = await withCheckedContinuation { continuation in
            service.cleanSelected { continuation.resume(returning: $0) }
        }
        #expect(result.itemCount == 1 && result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
        // it went to the Trash, not oblivion
        #expect(result.trashedURLs.count == 1)
        #expect(result.trashedURLs.allSatisfy { $0.path.contains("/.Trash/") && FileManager.default.fileExists(atPath: $0.path) })
        result.trashedURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Review fix: "dir/.*" globs also return "dir/." and "dir/..", which would clean the folder itself.
    @Test func dotEntriesNeverBecomeItems() throws {
        _ = try makeFile(".hidden", bytes: 10)
        let t = target(".*")
        let names = DiskCleanService.scan([t]).scans[t.id]?.items.map(\.name) ?? []
        #expect(names == [".hidden"])
        let result = DiskCleanService.clean([(root.appendingPathComponent("."), 0, false)])
        #expect(result.itemCount == 0 && FileManager.default.fileExists(atPath: root.path))
    }

    @Test func permanentTargetDeletesInsteadOfTrashing() throws {
        let file = try makeFile("gone.tmp", bytes: 10)
        let result = DiskCleanService.clean([(file, 10, true)])
        #expect(result.itemCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func symlinkedParentEscapingPolicyIsRefused() throws {
        // a symlink inside an allowed folder pointing at a protected one
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/usr")
        let result = DiskCleanService.clean([(link.appendingPathComponent("bin"), 0, true)])
        #expect(result.itemCount == 0 && result.failures.count == 1)
    }

    @Test func deselectionPersistsAndDefaultsSkipPersonalFiles() {
        let defaults = makeDefaults()
        let service = DiskCleanService(defaults: defaults)
        let trash = service.builtInTargets.first { $0.category == .trash }!
        let caches = service.builtInTargets.first { $0.category == .caches }!
        #expect(!service.isSelected(trash) && service.isSelected(caches))
        service.setSelected(false, for: caches)
        #expect(!DiskCleanService(defaults: defaults).isSelected(caches))
    }

    @Test func customTargetsPersist() {
        let defaults = makeDefaults()
        let service = DiskCleanService(defaults: defaults, builtInTargets: [])
        let t = target("*.log", category: .logs)
        service.addCustomTarget(t)
        #expect(DiskCleanService(defaults: defaults, builtInTargets: []).customTargets == [t])
        service.removeCustomTarget(id: t.id)
        #expect(DiskCleanService(defaults: defaults, builtInTargets: []).customTargets.isEmpty)
    }

    @Test func trashSelectionIsFlagged() async throws {
        _ = try makeFile("x.tmp", bytes: 10)
        let service = DiskCleanService(defaults: makeDefaults(), builtInTargets: [])
        var builtInTrash = target("*.tmp", category: .trash)
        builtInTrash.isBuiltIn = true
        let service2 = DiskCleanService(defaults: makeDefaults(), builtInTargets: [builtInTrash])
        service2.setSelected(true, for: builtInTrash)
        try await scanAndWait(service2)
        #expect(service2.selectionEmptiesTrash)
        // a custom target filed under "Trash" still goes to the Trash
        service.addCustomTarget(target("*.tmp", category: .trash))
        try await scanAndWait(service)
        #expect(!service.selectionEmptiesTrash)
    }

    private func scanAndWait(_ service: DiskCleanService) async throws {
        service.scan()
        for _ in 0..<200 where service.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!service.isScanning)
    }
}
