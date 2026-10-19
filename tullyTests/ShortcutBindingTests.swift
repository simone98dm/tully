import CoreGraphics
import Foundation
import Testing
@testable import tully

struct ShortcutBindingTests {
    @Test func dropsDeviceAndLockFlags() {
        // arrow keys carry fn + numeric-pad bits; Caps Lock adds alphaShift
        let raw: CGEventFlags = [.maskControl, .maskAlternate, .maskSecondaryFn, .maskNumericPad, .maskAlphaShift]
        let binding = ShortcutBinding(keyCode: 123, modifiers: raw.rawValue)
        #expect(binding == ShortcutBinding(keyCode: 123, modifiers: CGEventFlags([.maskControl, .maskAlternate]).rawValue))
    }

    @Test func displayStringOrdersModifiersLikeMacOS() {
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        #expect(ShortcutBinding(keyCode: 0, modifiers: flags.rawValue).displayString == "⌃⌥⇧⌘A")
        #expect(ShortcutBinding(keyCode: 123, modifiers: CGEventFlags.maskControl.rawValue).displayString == "⌃←")
        #expect(ShortcutBinding(keyCode: 18, modifiers: CGEventFlags.maskCommand.rawValue).displayString == "⌘1")
        #expect(ShortcutBinding(keyCode: 122, modifiers: CGEventFlags.maskCommand.rawValue).displayString == "⌘F1")
    }

    @Test func unknownKeyIsReadable() {
        #expect(ShortcutBinding(keyCode: 200, modifiers: CGEventFlags.maskCommand.rawValue).displayString == "⌘Key 200")
    }

    @Test func validation() {
        #expect(ShortcutBinding(keyCode: 0, modifiers: 0).validationError != nil)
        #expect(ShortcutBinding(keyCode: 0, modifiers: CGEventFlags.maskShift.rawValue).validationError != nil)
        #expect(ShortcutBinding(keyCode: 53, modifiers: CGEventFlags.maskCommand.rawValue).validationError != nil)
        #expect(ShortcutBinding(keyCode: 0, modifiers: CGEventFlags.maskAlternate.rawValue).validationError == nil)
    }

    @Test func codableRoundTripNormalizesLegacyData() throws {
        // pre-v2 builds stored raw flags including the non-coalesced bit
        let legacy = #"{"keyCode":123,"modifiers":\#(CGEventFlags([.maskControl, .maskNonCoalesced]).rawValue)}"#
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: Data(legacy.utf8))
        #expect(decoded == ShortcutBinding(keyCode: 123, modifiers: CGEventFlags.maskControl.rawValue))
        let again = try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(decoded))
        #expect(again == decoded)
    }
}

@MainActor
struct KeyboardLayoutTests {
    @Test func currentLayoutNamesLetterKeys() {
        let names = KeyboardLayout.currentNames()
        // every Latin layout has a letter on the A key position
        #expect(names[0]?.count == 1)
        #expect(names[123] == nil) // arrows keep their symbols
    }

    @Test func layoutNamesOverrideFallback() {
        let saved = ShortcutBinding.layoutKeyNames
        defer { ShortcutBinding.layoutKeyNames = saved }
        ShortcutBinding.layoutKeyNames = [16: "Z"] // QWERTZ
        #expect(ShortcutBinding.keyName(16) == "Z")
        #expect(ShortcutBinding.keyName(123) == "←")
    }
}
