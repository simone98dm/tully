// tully/Modules/SystemMonitor/SystemSampler.swift
import Darwin
import Foundation

struct SystemSampler {
    private var prevCPU: host_cpu_load_info_data_t?
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevProcTicks: [Int32: UInt64] = [:]
    private let sampleInterval: Double = 2.0

    // Called every 2s on background thread. Returns updated snapshot.
    mutating func sample() -> SystemSnapshot {
        let cpu   = sampleCPU()
        let ram   = sampleRAM()
        let disk  = sampleDisk()
        let net   = sampleNetwork()
        let procs = topProcesses()
        return SystemSnapshot(
            cpuPercent: cpu,
            ramUsed:    ram.used,
            ramTotal:   ram.total,
            diskUsed:   disk.used,
            diskTotal:  disk.total,
            netIn:      net.inBytes,
            netOut:     net.outBytes,
            topCPU:     procs.cpu,
            topRAM:     procs.ram
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

        let totalDelta = (user + system + idle + nice) - (pUser + pSystem + pIdle + pNice)
        let usedDelta  = (user + system + nice) - (pUser + pSystem + pNice)
        guard totalDelta > 0 else { return 0 }
        return min(100.0, (usedDelta / totalDelta) * 100.0)
    }

    // MARK: RAM

    private func sampleRAM() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let page = UInt64(vm_kernel_page_size)
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * page
        let total = UInt64(Foundation.ProcessInfo.processInfo.physicalMemory)
        return (used, total)
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

    private mutating func sampleNetwork() -> (inBytes: Double, outBytes: Double) {
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

        let inDelta  = totalIn  >= prevNetIn  ? Double(totalIn  - prevNetIn)  : 0
        let outDelta = totalOut >= prevNetOut ? Double(totalOut - prevNetOut) : 0
        prevNetIn  = totalIn
        prevNetOut = totalOut
        return (inDelta / sampleInterval, outDelta / sampleInterval)
    }

    // MARK: Top Processes

    private mutating func topProcesses() -> (cpu: [ProcessInfo], ram: [ProcessInfo]) {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return ([], []) }

        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let actual = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard actual > 0 else { return ([], []) }

        var results: [ProcessInfo] = []

        for i in 0..<Int(actual) {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, infoSize) == infoSize else { continue }

            var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)

            let currentTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let prevTicks    = prevProcTicks[pid] ?? currentTicks
            prevProcTicks[pid] = currentTicks

            let tickDeltaNs = currentTicks > prevTicks ? Double(currentTicks - prevTicks) : 0
            let cpuPercent  = (tickDeltaNs / (sampleInterval * 1_000_000_000.0)) * 100.0

            results.append(ProcessInfo(
                pid: pid,
                name: name.isEmpty ? "pid:\(pid)" : name,
                cpuPercent: cpuPercent,
                ramBytes: taskInfo.pti_resident_size
            ))
        }

        let topCPU = Array(results.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        let topRAM = Array(results.sorted { $0.ramBytes   > $1.ramBytes   }.prefix(5))
        return (topCPU, topRAM)
    }
}
