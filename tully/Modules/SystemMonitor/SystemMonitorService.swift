// tully/Modules/SystemMonitor/SystemMonitorService.swift
import Darwin
import Foundation

@Observable
final class SystemMonitorService {
    var snapshot = SystemSnapshot()
    private(set) var networkHistory: [(netIn: Double, netOut: Double)] = []
    private(set) var localIP: String = "—"

    private var samplerTask: Task<Void, Never>?
    private var tickCount = 0

    func start() {
        guard samplerTask == nil else { return }
        localIP = Self.resolveLocalIP()
        samplerTask = Task.detached(priority: .utility) { [weak self] in
            var sampler = SystemSampler()
            while !Task.isCancelled {
                let snap = sampler.sample()
                let entry = (netIn: snap.netIn, netOut: snap.netOut)
                await MainActor.run {
                    guard let self else { return }
                    self.snapshot = snap
                    self.networkHistory.append(entry)
                    if self.networkHistory.count > 30 { self.networkHistory.removeFirst() }
                    self.tickCount += 1
                    if self.tickCount % 5 == 0 { self.localIP = Self.resolveLocalIP() }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        samplerTask?.cancel()
        samplerTask = nil
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
