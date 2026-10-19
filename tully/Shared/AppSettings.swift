import Foundation
import SwiftUI

@Observable
final class AppSettings {
    private enum Key {
        static let showCPU = "tully.showCPU"
        static let showRAM = "tully.showRAM"
        static let showNet = "tully.showNet"
        static let showDisk = "tully.showDisk"
        static let statusStyle = "tully.statusStyle"
        static let statusOrder = "tully.statusOrder"
        static let statusTint = "tully.statusTint"
        static let all = [showCPU, showRAM, showNet, showDisk, statusStyle, statusOrder, statusTint]
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// Fires after any change so the menu bar can redraw right away.
    @ObservationIgnored var onChange: (() -> Void)?

    var showCPU: Bool { didSet { save(showCPU, Key.showCPU) } }
    var showRAM: Bool { didSet { save(showRAM, Key.showRAM) } }
    var showNet: Bool { didSet { save(showNet, Key.showNet) } }
    var showDisk: Bool { didSet { save(showDisk, Key.showDisk) } }
    var statusStyle: StatusStyle { didSet { save(statusStyle.rawValue, Key.statusStyle) } }
    /// Display order of the menu bar metrics.
    var statusOrder: [StatusMetric] { didSet { save(statusOrder.map(\.rawValue), Key.statusOrder) } }
    /// Colour metrics orange/red above the warning thresholds.
    var tintsHighUsage: Bool { didSet { save(tintsHighUsage, Key.statusTint) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showCPU = defaults.bool(forKey: Key.showCPU)
        showRAM = defaults.bool(forKey: Key.showRAM)
        showNet = defaults.bool(forKey: Key.showNet)
        showDisk = defaults.bool(forKey: Key.showDisk)
        statusStyle = defaults.string(forKey: Key.statusStyle).flatMap(StatusStyle.init) ?? .iconValue
        statusOrder = Self.completeOrder(defaults.stringArray(forKey: Key.statusOrder)?.compactMap(StatusMetric.init) ?? [])
        tintsHighUsage = defaults.object(forKey: Key.statusTint) as? Bool ?? true
    }

    func isShown(_ metric: StatusMetric) -> Bool {
        switch metric {
        case .cpu: showCPU
        case .ram: showRAM
        case .disk: showDisk
        case .net: showNet
        }
    }

    func setShown(_ metric: StatusMetric, _ value: Bool) {
        switch metric {
        case .cpu: showCPU = value
        case .ram: showRAM = value
        case .disk: showDisk = value
        case .net: showNet = value
        }
    }

    /// Enabled metrics in display order.
    var visibleMetrics: [StatusMetric] { statusOrder.filter(isShown) }

    func moveMetric(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = statusOrder
        order.move(fromOffsets: source, toOffset: destination)
        statusOrder = order
    }

    func resetAll() {
        Key.all.forEach(defaults.removeObject(forKey:))
        showCPU = false
        showRAM = false
        showNet = false
        showDisk = false
        statusStyle = .iconValue
        statusOrder = StatusMetric.allCases
        tintsHighUsage = true
        Key.all.forEach(defaults.removeObject(forKey:))
    }

    /// Keeps saved order and appends metrics added in newer versions.
    static func completeOrder(_ saved: [StatusMetric]) -> [StatusMetric] {
        var seen = Set<StatusMetric>()
        let unique = saved.filter { seen.insert($0).inserted }
        return unique + StatusMetric.allCases.filter { !seen.contains($0) }
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
