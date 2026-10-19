// tully/Shared/Models.swift
import Foundation
import CoreGraphics

// MARK: - System Monitor

nonisolated struct SystemSnapshot: Sendable {
    var cpuPercent: Double = 0
    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var ramWired: UInt64 = 0
    var ramCompressed: UInt64 = 0
    var diskUsed: Int64 = 0
    var diskTotal: Int64 = 0
    var netIn: Double = 0   // bytes/s
    var netOut: Double = 0  // bytes/s
    var processes: [ProcessInfo] = []
    var sensors = SensorReadings()

    var ramFraction: Double { ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) : 0 }
    var diskFraction: Double { diskTotal > 0 ? min(1, Double(diskUsed) / Double(diskTotal)) : 0 }
}

nonisolated struct ProcessInfo: Identifiable, Sendable, Hashable {
    var pid: Int32
    var id: Int32 { pid }
    var parentPID: Int32 = 0
    var name: String
    var path: String = ""
    var isSystem: Bool = false
    var cpuPercent: Double
    var ramBytes: UInt64
}

nonisolated struct FolderInfo: Identifiable, Sendable {
    let id = UUID()
    var url: URL
    var bytes: Int64

    var name: String { url.lastPathComponent }
}

// MARK: - Shortcuts

nonisolated struct ShortcutBinding: Codable, Hashable, Sendable {
    static let userModifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    var keyCode: UInt16
    var modifiers: UInt64 // CGEventFlags.rawValue, limited to `userModifiers`

    init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        // drop Caps Lock / fn / numeric-pad bits so bindings compare reliably (arrow keys carry fn + numpad)
        self.modifiers = modifiers & Self.userModifiers.rawValue
    }

    // decode through init so bindings saved by older versions (with device-specific bits) still match
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifiers: try container.decode(UInt64.self, forKey: .modifiers)
        )
    }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers }

    /// Global shortcuts need ⌘, ⌃ or ⌥ so they don't hijack normal typing.
    var hasCommandLikeModifier: Bool {
        !CGEventFlags(rawValue: modifiers).isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
    }

    /// Why this binding can't be used as a global shortcut, or nil when it's fine.
    var validationError: String? {
        if keyCode == Self.escapeKeyCode { return "Esc can't be used in a shortcut" }
        if !hasCommandLikeModifier { return "Add ⌘, ⌃ or ⌥ so the shortcut doesn't block typing" }
        return nil
    }

    var displayString: String {
        Self.modifierSymbols(CGEventFlags(rawValue: modifiers)) + Self.keyName(keyCode)
    }

    /// Filled from the current keyboard layout at launch (KeyboardLayout.refresh); US names otherwise.
    nonisolated(unsafe) static var layoutKeyNames: [UInt16: String] = [:]

    static func keyName(_ code: UInt16) -> String {
        layoutKeyNames[code] ?? keyNames[code] ?? "Key \(code)"
    }

    static func modifierSymbols(_ flags: CGEventFlags) -> String {
        var parts = ""
        if flags.contains(.maskControl)   { parts += "⌃" }
        if flags.contains(.maskAlternate) { parts += "⌥" }
        if flags.contains(.maskShift)     { parts += "⇧" }
        if flags.contains(.maskCommand)   { parts += "⌘" }
        return parts
    }

    static let escapeKeyCode: UInt16 = 53

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
