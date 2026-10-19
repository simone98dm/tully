import Foundation

/// Deterministic sample data for screenshots (`--demo-data`), so docs never show the real machine.
enum DemoData {
    static let processes: [ProcessInfo] = [
        process(101, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", cpu: 12.4, ram: 1_800),
        process(102, "Safari Web Content", "/Applications/Safari.app/Contents/XPCServices/WebContent", parent: 101, cpu: 6.1, ram: 950),
        process(103, "Xcode", "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 18.2, ram: 2_400),
        process(104, "Music", "/System/Applications/Music.app/Contents/MacOS/Music", cpu: 2.3, ram: 420),
        process(105, "Mail", "/System/Applications/Mail.app/Contents/MacOS/Mail", cpu: 0.8, ram: 380),
        process(106, "Notes", "/System/Applications/Notes.app/Contents/MacOS/Notes", cpu: 0.4, ram: 260),
        process(107, "Finder", "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", cpu: 0.6, ram: 210),
        process(108, "WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/WindowServer", system: true, cpu: 9.5, ram: 640),
        process(109, "kernel_task", "", system: true, cpu: 4.2, ram: 900),
    ]

    private static func process(_ pid: Int32, _ name: String, _ path: String, parent: Int32 = 1, system: Bool = false,
                                cpu: Double, ram: UInt64) -> ProcessInfo {
        ProcessInfo(pid: pid, parentPID: parent, name: name, path: path, isSystem: system, cpuPercent: cpu, ramBytes: ram << 20)
    }

    /// Snapshot `step` of a gentle, repeating load curve.
    static func snapshot(step: Int) -> SystemSnapshot {
        let wave = (sin(Double(step) / 6) + 1) / 2
        var snap = SystemSnapshot()
        snap.cpuPercent = 18 + 22 * wave
        snap.ramTotal = 16 << 30
        snap.ramUsed = UInt64(Double(9 << 30) + Double(2 << 30) * wave)
        snap.ramWired = 2 << 30
        snap.ramCompressed = 1 << 30
        snap.diskTotal = 494 << 30
        snap.diskUsed = 312 << 30
        snap.netIn = 180_000 + 900_000 * wave * wave
        snap.netOut = 40_000 + 120_000 * (1 - wave)
        snap.processes = processes
        snap.sensors = SensorReadings(gpuPercent: 14 + 10 * wave, cpuTemperature: 46 + 6 * wave,
                                      gpuTemperature: 41 + 4 * wave, fanRPMs: [])
        return snap
    }

    static let folders: [FolderInfo] = [
        ("Library", 61), ("Movies", 48), ("Developer", 32), ("Pictures", 21), ("Music", 14),
        ("Documents", 9), ("Downloads", 6), ("Desktop", 2),
    ].map { FolderInfo(url: URL(fileURLWithPath: "/Users/demo/\($0.0)"), bytes: Int64($0.1) << 30) }

    /// Sample data for every screen that shows numbers.
    static func fill(_ monitor: SystemMonitorService, disk: DiskScanService, settings: AppSettings) {
        disk.publish(folders, finished: true)
        settings.showCPU = true
        settings.showRAM = true
        settings.showNet = true
        fill(monitor)
    }

    static func fill(_ monitor: SystemMonitorService) {
        let groups = ProcessGroup.build(from: processes)
        for step in 0..<SystemMonitorService.historyLength {
            _ = monitor.apply(snapshot(step: step), groups: groups)
        }
    }
}
