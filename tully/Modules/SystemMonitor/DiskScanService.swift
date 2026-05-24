// tully/Modules/SystemMonitor/DiskScanService.swift
import Foundation

@Observable
final class DiskScanService {
    var topFolders: [FolderInfo] = []
    var isScanning = false
    var lastScanDate: Date?

    private var scanTask: Task<Void, Never>?

    func scan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        isScanning = true
        topFolders = []

        scanTask = Task.detached(priority: .utility) { [weak self] in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            guard let topLevel = try? fm.contentsOfDirectory(
                at: home,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run { self?.isScanning = false }
                return
            }

            var accumulated: [FolderInfo] = []

            for url in topLevel {
                guard !Task.isCancelled else { break }
                let bytes = Self.allocatedSize(of: url, fm: fm)
                guard bytes > 0 else { continue }
                accumulated.append(FolderInfo(url: url, bytes: bytes))
                // Progressive update: sort and push after each folder so UI fills in gradually
                let sorted = accumulated.sorted { $0.bytes > $1.bytes }
                await MainActor.run { self?.topFolders = sorted }
            }

            await MainActor.run {
                self?.isScanning = false
                self?.lastScanDate = Date()
            }
        }
    }

    // Recursive allocated size via FileManager — no subprocess, single TCC grant remembered by OS.
    private nonisolated static func allocatedSize(of url: URL, fm: FileManager) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true } // skip inaccessible items silently
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard !Task.isCancelled else { break }
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
