import CoreGraphics
import Foundation
import Testing
@testable import tully

@MainActor
struct KeyboardShortcutHandlerTests {
    let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]

    @Test func consumesBoundShortcutAndReportsZone() async {
        let handler = KeyboardShortcutHandler()
        handler.bindings = [ShortcutBinding(keyCode: KeyCode.left, modifiers: ctrlOpt.rawValue): .leftHalf]
        let received = ZoneBox()
        handler.onZoneTriggered = { zone in received.set(zone) }

        // real arrow events carry fn + numpad flags
        let event = keyEvent(KeyCode.left, flags: ctrlOpt.union([.maskSecondaryFn, .maskNumericPad]))
        #expect(handler.handle(type: .keyDown, event: event))
        await drainMainQueue()
        #expect(received.value == .leftHalf)
    }

    @Test func ignoresOtherKeysAndKeyUp() {
        let handler = KeyboardShortcutHandler()
        handler.bindings = [ShortcutBinding(keyCode: KeyCode.left, modifiers: ctrlOpt.rawValue): .leftHalf]
        #expect(!handler.handle(type: .keyDown, event: keyEvent(KeyCode.right, flags: ctrlOpt)))
        #expect(!handler.handle(type: .keyDown, event: keyEvent(KeyCode.left)))
        #expect(!handler.handle(type: .keyUp, event: keyEvent(KeyCode.left, down: false, flags: ctrlOpt)))
    }
}

final class ZoneBox: @unchecked Sendable {
    private let lock = NSLock()
    private var zone: WindowZone?
    var value: WindowZone? { lock.withLock { zone } }
    func set(_ value: WindowZone) { lock.withLock { zone = value } }
}
