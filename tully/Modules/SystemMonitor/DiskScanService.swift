import Foundation

@Observable
final class DiskScanService {
    private(set) var topFolders: [FolderInfo] = []
    private(set) var isScanning = false
    private(set) var lastScanDate: Date?

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.root = root
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        topFolders = []
        let root = root
        scanTask = Task.detached(priority: .utility) { [weak self] in
            let topLevel = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            var accumulated: [FolderInfo] = []
            for url in topLevel {
                guard !Task.isCancelled else { break }
                let bytes = Self.allocatedSize(of: url)
                guard bytes > 0 else { continue }
                accumulated.append(FolderInfo(url: url, bytes: bytes))
                // progressive update so the list fills in while scanning
                await self?.publish(accumulated.sorted { $0.bytes > $1.bytes }, finished: false)
            }
            await self?.publish(accumulated.sorted { $0.bytes > $1.bytes }, finished: true)
        }
    }

    func cancel() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func publish(_ folders: [FolderInfo], finished: Bool) {
        topFolders = folders
        if finished {
            isScanning = false
            lastScanDate = Date()
        }
    }

    /// Recursive allocated size via FileManager (no subprocess). Skips unreadable items.
    nonisolated static func allocatedSize(of url: URL, fm: FileManager = .default) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
        let ownValues = try? url.resourceValues(forKeys: keys)
        guard ownValues?.isDirectory == true else {
            return Int64(ownValues?.totalFileAllocatedSize ?? ownValues?.fileAllocatedSize ?? 0)
        }
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
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
