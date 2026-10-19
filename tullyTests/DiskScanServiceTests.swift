import Foundation
import Testing
@testable import tully

@MainActor
struct DiskScanServiceTests {
    @Test func measuresAndSortsTopLevelFolders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tully-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, bytes) in [("small", 1_000), ("big", 300_000), ("medium", 60_000)] {
            let folder = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try Data(count: bytes).write(to: folder.appendingPathComponent("nested/file"))
        }
        let service = DiskScanService(root: root)
        service.scan()
        #expect(service.isScanning)
        for _ in 0..<300 where service.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!service.isScanning && service.lastScanDate != nil)
        #expect(service.topFolders.map(\.name) == ["big", "medium", "small"])
        #expect(service.topFolders[0].bytes >= 300_000)
    }

    @Test func missingRootFinishesEmpty() async throws {
        let service = DiskScanService(root: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        service.scan()
        for _ in 0..<100 where service.isScanning { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!service.isScanning && service.topFolders.isEmpty)
    }

    @Test func allocatedSizeOfAFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tully-size-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(count: 10_000).write(to: file)
        #expect(DiskScanService.allocatedSize(of: file) >= 10_000)
    }
}
