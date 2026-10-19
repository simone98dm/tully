import Foundation

nonisolated func formatBytes<T: BinaryInteger>(_ bytes: T, style: ByteCountFormatter.CountStyle = .memory) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = style
    formatter.allowsNonnumericFormatting = false // "0 KB", not "Zero KB"
    return formatter.string(fromByteCount: Int64(bytes))
}

/// Compact network rate for tight spaces like the menu bar: "840B/s", "12KB/s", "3.4MB/s".
nonisolated func formatRate(_ bytesPerSecond: Double) -> String {
    let bps = max(0, bytesPerSecond)
    if bps >= 1_048_576 { return String(format: "%.1fMB/s", bps / 1_048_576) }
    if bps >= 1024 { return String(format: "%.0fKB/s", bps / 1024) }
    return "\(Int(bps))B/s"
}

nonisolated func formatTemperature(_ celsius: Double) -> String {
    Measurement(value: celsius, unit: UnitTemperature.celsius)
        .formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
}
