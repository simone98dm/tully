// tully/Modules/SystemMonitor/DiskScanService.swift
import Foundation

@Observable
final class DiskScanService {
    var topFolders: [FolderInfo] = []
    var isScanning = false
    var lastScanDate: Date?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) {
            let folders = await DiskScanService.runScan()
            await MainActor.run { [weak self] in
                self?.topFolders = folders
                self?.isScanning = false
                self?.lastScanDate = Date()
            }
        }
    }

    private static func runScan() async -> [FolderInfo] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "du -sk \"\(home)\"/* 2>/dev/null"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() } catch { return [] }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [FolderInfo] = []
        for line in output.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2,
                  let kbSize = Int64(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            results.append(FolderInfo(url: url, bytes: kbSize * 1024))
        }

        return results.sorted { $0.bytes > $1.bytes }
    }
}
