import Darwin
import Foundation

nonisolated struct SystemSampler {
    private var prevCPU: host_cpu_load_info_data_t?
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevProcTicks: [Int32: UInt64] = [:]
    private var lastSampleTime: ContinuousClock.Instant?
    /// Executable path and display name per pid; looking them up for every process each tick is the
    /// sampler's biggest cost. Entries for exited pids are dropped every sample.
    private var identityCache: [Int32: (path: String, name: String)] = [:]
    private let sensorReader = SensorReader()
    /// pti_total_* are Mach absolute-time ticks (not ns on Apple Silicon).
    private static let nanosecondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    // Called periodically on a background task. Returns updated snapshot.
    /// `includeProcesses: false` skips the per-process walk and sensors (nothing on screen needs them).
    mutating func sample(includeProcesses: Bool = true) -> SystemSnapshot {
        let now = ContinuousClock.now
        let elapsed = lastSampleTime.map { (now - $0) / .seconds(1) } ?? 1
        lastSampleTime = now
        let interval = max(elapsed, 0.1)

        let ram  = sampleRAM()
        let disk = sampleDisk()
        let net  = sampleNetwork(interval: interval)
        return SystemSnapshot(
            cpuPercent: sampleCPU(),
            ramUsed:    ram.used,
            ramTotal:   ram.total,
            ramWired:   ram.wired,
            ramCompressed: ram.compressed,
            diskUsed:   disk.used,
            diskTotal:  disk.total,
            netIn:      net.inBytes,
            netOut:     net.outBytes,
            processes:  includeProcesses ? sampleProcesses(interval: interval) : [],
            sensors:    includeProcesses ? sensorReader.read() : SensorReadings()
        )
    }

    // MARK: CPU

    private mutating func sampleCPU() -> Double {
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { prevCPU = info }

        let user   = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle   = Double(info.cpu_ticks.2)
        let nice   = Double(info.cpu_ticks.3)

        guard let prev = prevCPU else { return 0 }
        let pUser   = Double(prev.cpu_ticks.0)
        let pSystem = Double(prev.cpu_ticks.1)
        let pIdle   = Double(prev.cpu_ticks.2)
        let pNice   = Double(prev.cpu_ticks.3)

        return Self.cpuPercent(used: user + system + nice, idle: idle, previousUsed: pUser + pSystem + pNice, previousIdle: pIdle)
    }

    static func cpuPercent(used: Double, idle: Double, previousUsed: Double, previousIdle: Double) -> Double {
        let totalDelta = (used + idle) - (previousUsed + previousIdle)
        let usedDelta = used - previousUsed
        guard totalDelta > 0 else { return 0 }
        return min(100.0, max(0, usedDelta / totalDelta * 100.0))
    }

    /// Bytes per second from two counter readings; a counter that went backwards (interface reset) reads 0.
    static func rate(current: UInt64, previous: UInt64, interval: Double) -> Double {
        current >= previous ? Double(current - previous) / max(interval, 0.1) : 0
    }

    // MARK: RAM

    private func sampleRAM() -> (used: UInt64, total: UInt64, wired: UInt64, compressed: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0, 0) }
        let memory = Self.memoryUsage(active: UInt64(stats.active_count), wired: UInt64(stats.wire_count),
                                      compressed: UInt64(stats.compressor_page_count), pageSize: UInt64(vm_kernel_page_size))
        return (memory.used, UInt64(Foundation.ProcessInfo.processInfo.physicalMemory), memory.wired, memory.compressed)
    }

    /// "Used" memory as Activity Monitor counts it: active + wired + compressed pages.
    static func memoryUsage(active: UInt64, wired: UInt64, compressed: UInt64, pageSize: UInt64)
        -> (used: UInt64, wired: UInt64, compressed: UInt64) {
        ((active + wired + compressed) * pageSize, wired * pageSize, compressed * pageSize)
    }

    // MARK: Disk

    private func sampleDisk() -> (used: Int64, total: Int64) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = attrs[.systemSize] as? Int64,
              let free  = attrs[.systemFreeSize] as? Int64
        else { return (0, 0) }
        return (total - free, total)
    }

    // MARK: Network

    private mutating func sampleNetwork(interval: Double) -> (inBytes: Double, outBytes: Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(first) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            let flags = Int32(cur.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp       = (flags & IFF_UP) != 0
            let isLink     = cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)
            if !isLoopback && isUp && isLink,
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                totalIn  += UInt64(data.pointee.ifi_ibytes)
                totalOut += UInt64(data.pointee.ifi_obytes)
            }
            cursor = cur.pointee.ifa_next
        }

        defer {
            prevNetIn = totalIn
            prevNetOut = totalOut
        }
        // the first sample has no baseline; report 0 rather than the counters since boot
        guard prevNetIn > 0 || prevNetOut > 0 else { return (0, 0) }
        return (Self.rate(current: totalIn, previous: prevNetIn, interval: interval),
                Self.rate(current: totalOut, previous: prevNetOut, interval: interval))
    }

    // MARK: Processes

    private mutating func sampleProcesses(interval: Double) -> [ProcessInfo] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return [] }

        var results: [ProcessInfo] = []
        var seenTicks: [Int32: UInt64] = [:]

        for pid in pids.prefix(Int(actual)) where pid > 0 {
            var taskInfo = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize else { continue }

            var bsdInfo = proc_bsdinfo()
            let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
            let hasBSD = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize

            let currentTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let prevTicks    = prevProcTicks[pid] ?? currentTicks
            seenTicks[pid] = currentTicks
            let tickDeltaNs  = currentTicks > prevTicks ? Double(currentTicks - prevTicks) * Self.nanosecondsPerTick : 0

            let identity = identityCache[pid] ?? {
                let path = executablePath(for: pid)
                return (path, friendlyName(for: pid, path: path))
            }()
            identityCache[pid] = identity
            let path = identity.path
            results.append(ProcessInfo(
                pid: pid,
                parentPID: hasBSD ? Int32(bsdInfo.pbi_ppid) : 0,
                name: identity.name,
                path: path,
                isSystem: Self.isSystemProcess(path: path, uid: hasBSD ? bsdInfo.pbi_uid : 0),
                cpuPercent: tickDeltaNs / (interval * 1_000_000_000.0) * 100.0,
                ramBytes: taskInfo.pti_resident_size
            ))
        }
        prevProcTicks = seenTicks // drop exited pids
        identityCache = identityCache.filter { seenTicks[$0.key] != nil }
        return results
    }

    private static func isSystemProcess(path: String, uid: uid_t) -> Bool {
        guard !path.contains(".app/") else { return false }
        return uid == 0 || ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    private func executablePath(for pid: Int32) -> String {
        var pathBuf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { return "" }
        return String(cString: pathBuf)
    }

    // Returns a human-readable process name using the full executable path.
    // Prefers the .app bundle name (e.g. "Safari") over the raw binary name.
    private func friendlyName(for pid: Int32, path: String) -> String {
        guard !path.isEmpty else {
            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let n = String(cString: nameBuf)
            return n.isEmpty ? "pid:\(pid)" : n
        }
        // /Applications/Safari.app/Contents/MacOS/Safari → "Safari"
        if let appComponent = path.components(separatedBy: "/").first(where: { $0.hasSuffix(".app") }) {
            return String(appComponent.dropLast(4))
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
