import Darwin
import Foundation

nonisolated struct UsagePoint: Sendable {
    var cpu: Double      // 0–1
    var memory: Double   // 0–1
    var gpu: Double      // 0–1
    var netIn: Double    // bytes/s
    var netOut: Double   // bytes/s
}

@Observable
final class SystemMonitorService {
    static let intervals: [Double] = [1, 2, 5, 10]
    static let historyLength = 120
    static let intervalKey = "tully.monitor.interval"

    private(set) var snapshot = SystemSnapshot()
    private(set) var history: [UsagePoint] = []
    private(set) var groups: [ProcessGroup] = []
    private(set) var localIP: String = "—"

    /// Seconds between samples.
    var interval: Double {
        didSet { defaults.set(interval, forKey: Self.intervalKey) }
    }

    /// Whether something on screen shows processes or sensors (popover, System Monitor window).
    /// When false the sampler only reads the cheap totals the menu bar needs.
    @ObservationIgnored var needsDetails: () -> Bool = { true }

    /// Called after each sample (drives the menu bar).
    @ObservationIgnored var onSample: ((SystemSnapshot) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var samplerTask: Task<Void, Never>?
    @ObservationIgnored private var tickCount = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.double(forKey: Self.intervalKey)
        interval = Self.intervals.contains(saved) ? saved : 2
    }

    /// Top groups by memory, for the compact popover list.
    func topGroupsByMemory(_ count: Int) -> [ProcessGroup] {
        Array(groups.sorted { $0.ramBytes > $1.ramBytes }.prefix(count))
    }

    func start() {
        guard samplerTask == nil else { return }
        localIP = Self.resolveLocalIP()
        samplerTask = Task.detached(priority: .utility) { [weak self] in
            var sampler = SystemSampler()
            while !Task.isCancelled {
                let details = await self?.needsDetails() ?? false
                let snap = sampler.sample(includeProcesses: details)
                let groups = ProcessGroup.build(from: snap.processes)
                guard let interval = await self?.apply(snap, groups: groups) else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
    }

    /// Publishes a sample; returns the delay before the next one. Internal for tests.
    func apply(_ snap: SystemSnapshot, groups: [ProcessGroup]) -> Double {
        // keep the last process list while nobody looks, so reopening shows data immediately
        let keepsOldDetails = snap.processes.isEmpty && !snapshot.processes.isEmpty
        snapshot = keepsOldDetails ? Self.merging(snap, detailsFrom: snapshot) : snap
        if !keepsOldDetails { self.groups = groups }
        history.append(UsagePoint(
            cpu: snap.cpuPercent / 100,
            memory: snap.ramFraction,
            gpu: (snap.sensors.gpuPercent ?? 0) / 100,
            netIn: snap.netIn,
            netOut: snap.netOut
        ))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        tickCount += 1
        if tickCount % 5 == 0 { localIP = Self.resolveLocalIP() }
        onSample?(snap)
        return interval
    }

    private static func merging(_ fresh: SystemSnapshot, detailsFrom old: SystemSnapshot) -> SystemSnapshot {
        var merged = fresh
        merged.processes = old.processes
        merged.sensors = old.sensors
        return merged
    }

    private static func resolveLocalIP() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return "—" }
        defer { freeifaddrs(first) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            let flags = Int32(cur.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp = (flags & IFF_UP) != 0
            let isIPv4 = cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET)
            if !isLoopback && isUp && isIPv4 {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let sa = cur.pointee.ifa_addr
                let saLen = socklen_t((sa?.pointee.sa_len ?? 0))
                if getnameinfo(sa, saLen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: buf)
                    if !ip.isEmpty { return ip }
                }
            }
            cursor = cur.pointee.ifa_next
        }
        return "—"
    }
}
