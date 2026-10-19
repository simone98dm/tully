import Carbon.HIToolbox
import Foundation

/// Names keys as printed on the user's keyboard layout (e.g. "Z" on QWERTZ where US has "Y").
enum KeyboardLayout {
    /// Character keys only; arrows, F-keys etc. keep their symbols.
    private static let characterKeyCodes: [UInt16] = Array(0...50).filter { ![36, 48, 49].contains($0) }.map(UInt16.init)

    /// Call at launch and when the input source changes.
    static func refresh() {
        ShortcutBinding.layoutKeyNames = currentNames()
    }

    static func currentNames() -> [UInt16: String] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> [UInt16: String] in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return [:] }
            var names: [UInt16: String] = [:]
            for code in characterKeyCodes {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let name = String(utf16CodeUnits: chars, count: length).uppercased()
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { names[code] = name }
            }
            return names
        }
    }
}
