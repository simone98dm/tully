import CoreGraphics
import Foundation
import Testing
@testable import tully

@MainActor
struct TabHotkeyHandlerTests {
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var log: [String] = []
        var all: [String] { lock.withLock { log } }
        func add(_ entry: String) { lock.withLock { log.append(entry) } }
    }

    func makeHandler(hotkey: ShortcutBinding) -> (TabHotkeyHandler, Events) {
        let handler = TabHotkeyHandler()
        let events = Events()
        handler.hotkey = hotkey
        handler.onActivate = { events.add("activate") }
        handler.onTab = { reverse in events.add(reverse ? "back" : "next") }
        handler.onConfirm = { events.add("confirm") }
        handler.onDismiss = { events.add("dismiss") }
        return (handler, events)
    }

    let optionSpace = ShortcutBinding(keyCode: KeyCode.space, modifiers: CGEventFlags.maskAlternate.rawValue)

    @Test func activateCycleAndConfirmOnModifierRelease() async {
        let (handler, events) = makeHandler(hotkey: optionSpace)
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.space, flags: .maskAlternate)))
        handler.isOverlayVisible = true
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.tab, flags: .maskAlternate)))
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.tab, flags: [.maskAlternate, .maskShift])))
        // releasing ⌥ confirms but passes the event through so the app sees a clean modifier state
        #expect(!handler.handle(type: .flagsChanged, event: flagsEvent([])))
        await drainMainQueue()
        #expect(events.all == ["activate", "next", "back", "confirm"])
    }

    @Test func returnConfirmsAndEscDismisses() async {
        let (handler, events) = makeHandler(hotkey: optionSpace)
        handler.isOverlayVisible = true
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.returnKey, flags: .maskAlternate)))
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.escape, flags: .maskAlternate)))
        await drainMainQueue()
        #expect(events.all == ["confirm", "dismiss"])
    }

    @Test func resetDismissesVisibleOverlay() async {
        let (handler, events) = makeHandler(hotkey: optionSpace)
        handler.isOverlayVisible = true
        handler.reset()
        #expect(!handler.isOverlayVisible)
        await drainMainQueue()
        #expect(events.all == ["dismiss"])
    }

    @Test func autoRepeatDoesNotReopen() async {
        let (handler, events) = makeHandler(hotkey: optionSpace)
        let repeatEvent = keyEvent(KeyCode.space, flags: .maskAlternate)
        repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(handler.handle(type: .keyDown, event: repeatEvent))
        await drainMainQueue()
        #expect(events.all.isEmpty)
    }

    @Test func tabIsIgnoredWhileHidden() {
        let (handler, _) = makeHandler(hotkey: optionSpace)
        #expect(!handler.handle(type: .keyDown, event: keyEvent(KeyCode.tab, flags: .maskAlternate)))
    }

    @Test func capsLockDoesNotBreakActivation() {
        let (handler, _) = makeHandler(hotkey: optionSpace)
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.space, flags: [.maskAlternate, .maskAlphaShift])))
    }

    @Test func plainKeyHotkeyConfirmsOnKeyUp() async {
        let f13 = ShortcutBinding(keyCode: 105, modifiers: 0)
        let (handler, events) = makeHandler(hotkey: f13)
        #expect(handler.handle(type: .keyDown, event: keyEvent(105)))
        handler.isOverlayVisible = true
        #expect(handler.handle(type: .keyUp, event: keyEvent(105, down: false)))
        await drainMainQueue()
        #expect(events.all == ["activate", "confirm"])
    }
}
