// tully/Shared/Models.swift
import Foundation
import CoreGraphics

// MARK: - System Monitor

struct SystemSnapshot: Sendable {
    var cpuPercent: Double = 0
    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var ramWired: UInt64 = 0
    var ramCompressed: UInt64 = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var netIn: Double = 0   // bytes/s
    var netOut: Double = 0  // bytes/s
    var topCPU: [ProcessInfo] = []
    var topRAM: [ProcessInfo] = []
    var topNet: [NetProcessInfo] = []
    var battery: BatteryInfo = BatteryInfo()
}

struct ProcessInfo: Identifiable, Sendable {
    let id = UUID()
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var ramBytes: UInt64
}

struct NetProcessInfo: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var connections: Int
}

struct BatteryInfo: Sendable {
    var isPresent: Bool = false
    var percentage: Int = 0
    var isCharging: Bool = false
    var isCharged: Bool = false
    var timeRemaining: Int = -1  // minutes; -1 = unknown/calculating
    var cycleCount: Int = 0
}

struct FolderInfo: Identifiable, Sendable {
    let id = UUID()
    var url: URL
    var bytes: Int64

    var name: String { url.lastPathComponent }
}

// MARK: - Window Manager

enum WindowZone: String, CaseIterable, Codable, Sendable {
    case leftHalf, rightHalf
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case fullscreen
    case topLeft, topRight, bottomLeft, bottomRight

    var displayName: String {
        switch self {
        case .leftHalf:       return "Left Half"
        case .rightHalf:      return "Right Half"
        case .leftThird:      return "Left ⅓"
        case .centerThird:    return "Center ⅓"
        case .rightThird:     return "Right ⅓"
        case .leftTwoThirds:  return "Left ⅔"
        case .rightTwoThirds: return "Right ⅔"
        case .fullscreen:     return "Fullscreen"
        case .topLeft:        return "Top-Left"
        case .topRight:       return "Top-Right"
        case .bottomLeft:     return "Bottom-Left"
        case .bottomRight:    return "Bottom-Right"
        }
    }
}

struct ShortcutBinding: Codable, Hashable, Sendable {
    var keyCode: UInt16
    var modifiers: UInt64 // CGEventFlags.rawValue

    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",
            11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",32:"U",34:"I",
            31:"O",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",
            123:"←",124:"→",125:"↓",126:"↑",
            36:"↩",48:"⇥",49:"Space",51:"⌫",53:"⎋",
        ]
        return map[code] ?? "(\(code))"
    }
}
