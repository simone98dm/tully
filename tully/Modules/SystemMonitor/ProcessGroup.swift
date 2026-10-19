import Foundation

/// A logical app: the parent process plus every child it spawned, with usage aggregated.
nonisolated struct ProcessGroup: Identifiable, Sendable {
    static let systemID = "system"
    private static let systemActivityThreshold = 0.1          // % CPU
    private static let systemMemoryThreshold: UInt64 = 100 << 20 // 100 MB

    let id: String
    let name: String
    /// The app's own process (what "Quit" should signal), not one of its helpers.
    var rootPID: Int32 = 0
    let iconPath: String?
    let members: [ProcessInfo]
    let cpuPercent: Double
    let ramBytes: UInt64

    var isSystem: Bool { id == Self.systemID }

    static func build(from processes: [ProcessInfo]) -> [ProcessGroup] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        func root(of process: ProcessInfo) -> ProcessInfo {
            var current = process
            // ponytail: depth cap guards against pid reuse creating parent cycles
            for _ in 0..<64 {
                guard current.parentPID > 1, let parent = byPID[current.parentPID] else { break }
                current = parent
            }
            return current
        }

        var buckets: [String: (root: ProcessInfo, members: [ProcessInfo])] = [:]
        for process in processes {
            let top = root(of: process)
            // XPC helpers launched by launchd share their app's name, so key by name to merge them
            let key = top.isSystem && process.isSystem ? systemID : top.name
            buckets[key, default: (top, [])].members.append(process)
        }

        return buckets.map { key, bucket in
            let isSystem = key == systemID
            let visibleMembers = isSystem
                ? bucket.members.filter { $0.cpuPercent >= systemActivityThreshold || $0.ramBytes >= systemMemoryThreshold }
                : bucket.members
            // icon from the outermost .app of any member; helpers often launch first
            let appPath = bucket.members.lazy.compactMap { member in
                member.path.range(of: ".app/").map { String(member.path[..<$0.lowerBound]) + ".app" }
            }.first
            return ProcessGroup(
                id: key,
                name: isSystem ? "System" : key,
                rootPID: bucket.root.pid,
                iconPath: isSystem ? nil : appPath ?? bucket.root.path,
                members: visibleMembers.sorted { $0.ramBytes > $1.ramBytes },
                cpuPercent: bucket.members.reduce(0) { $0 + $1.cpuPercent },
                ramBytes: bucket.members.reduce(0) { $0 + $1.ramBytes }
            )
        }
    }
}
