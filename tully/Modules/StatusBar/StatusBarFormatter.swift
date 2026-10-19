import Foundation

nonisolated enum StatusMetric: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu, ram, disk, net

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU usage"
        case .ram: "Memory used"
        case .disk: "Disk used"
        case .net: "Network download"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .disk: "internaldrive"
        case .net: "arrow.down"
        }
    }

    var shortLabel: String {
        switch self {
        case .cpu: "CPU"
        case .ram: "MEM"
        case .disk: "SSD"
        case .net: "NET"
        }
    }

    /// Widest value the metric shows; its slot is sized to this so the menu bar item never jitters.
    var widthTemplate: String {
        switch self {
        case .cpu, .disk: "100%"
        case .ram: "88.8GB"
        case .net: "888KB/s"
        }
    }
}

nonisolated enum StatusStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case iconValue, labelValue, compact, stacked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iconValue: "Icon and value"
        case .labelValue: "Label and value"
        case .compact: "Value only"
        case .stacked: "Stacked (two lines)"
        }
    }
}

nonisolated struct StatusSegment: Equatable, Sendable {
    let metric: StatusMetric
    let value: String
    let level: UsageLevel
    let spokenValue: String
}

/// Turns a snapshot into menu bar segments. Pure, so every combination is unit-tested.
nonisolated enum StatusBarFormatter {
    static let gigabyte = 1_073_741_824.0

    static func segments(for snapshot: SystemSnapshot, metrics: [StatusMetric]) -> [StatusSegment] {
        metrics.map { segment(for: $0, snapshot: snapshot) }
    }

    static func segment(for metric: StatusMetric, snapshot: SystemSnapshot) -> StatusSegment {
        switch metric {
        case .cpu:
            let value = min(100, max(0, snapshot.cpuPercent))
            return StatusSegment(metric: .cpu, value: String(format: "%.0f%%", value),
                                 level: UsageLevel(fraction: value / 100),
                                 spokenValue: String(format: "CPU %.0f percent", value))
        case .ram:
            let used = Double(snapshot.ramUsed) / gigabyte
            let fraction = snapshot.ramTotal > 0 ? Double(snapshot.ramUsed) / Double(snapshot.ramTotal) : 0
            return StatusSegment(metric: .ram, value: String(format: "%.1fGB", used),
                                 level: UsageLevel(fraction: fraction),
                                 spokenValue: String(format: "memory %.1f gigabytes", used))
        case .disk:
            let fraction = snapshot.diskTotal > 0 ? Double(snapshot.diskUsed) / Double(snapshot.diskTotal) : 0
            return StatusSegment(metric: .disk, value: String(format: "%.0f%%", fraction * 100),
                                 level: UsageLevel(fraction: fraction),
                                 spokenValue: String(format: "disk %.0f percent used", fraction * 100))
        case .net:
            let rate = formatRate(snapshot.netIn)
            return StatusSegment(metric: .net, value: rate, level: .normal, spokenValue: "download \(rate)")
        }
    }

    static func accessibilityLabel(for segments: [StatusSegment]) -> String {
        guard !segments.isEmpty else { return "tully" }
        return "tully: " + segments.map(\.spokenValue).joined(separator: ", ")
    }
}
