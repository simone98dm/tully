import AppKit
import CoreGraphics
import SwiftUI
import Foundation
import Testing
@testable import tully

struct RingLogicTests {
    @Test(arguments: [
        (CGVector(dx: 60, dy: 0), WindowZone.rightHalf),
        (CGVector(dx: 50, dy: 50), .topRight),
        (CGVector(dx: 0, dy: 60), .topHalf),
        (CGVector(dx: -50, dy: 50), .topLeft),
        (CGVector(dx: -60, dy: 0), .leftHalf),
        (CGVector(dx: -50, dy: -50), .bottomLeft),
        (CGVector(dx: 0, dy: -60), .bottomHalf),
        (CGVector(dx: 50, dy: -50), .bottomRight),
        (CGVector(dx: 200, dy: 0), .rightThird),
        (CGVector(dx: -200, dy: 5), .leftThird),
        (CGVector(dx: 0, dy: 200), .fullscreen),
        (CGVector(dx: 0, dy: -200), .centerThird),
        (CGVector(dx: 150, dy: 150), .topRight),
    ])
    func cursorOffsetsMapToZones(offset: CGVector, zone: WindowZone) {
        #expect(RingLogic.zone(for: offset, hubRadius: 30, outerRadius: 130) == zone)
    }

    @Test func hubCancels() {
        #expect(RingLogic.zone(for: CGVector(dx: 10, dy: -10), hubRadius: 30, outerRadius: 130) == nil)
    }

    @Test func sectorBoundariesAreStable() {
        // just either side of the 22.5° boundary between east and north-east
        let below = CGVector(dx: cos(0.38) * 80, dy: sin(0.38) * 80)
        let above = CGVector(dx: cos(0.41) * 80, dy: sin(0.41) * 80)
        #expect(RingLogic.direction(for: below, hubRadius: 30) == .east)
        #expect(RingLogic.direction(for: above, hubRadius: 30) == .northEast)
    }
}

@MainActor
struct RingKeyHandlerTests {
    final class Signals: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [RingKeyHandler.Signal] = []
        var all: [RingKeyHandler.Signal] { lock.withLock { list } }
        func add(_ signal: RingKeyHandler.Signal) { lock.withLock { list.append(signal) } }
    }

    let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]

    func makeHandler(mouseDown: Bool = false) -> (RingKeyHandler, Signals) {
        let handler = RingKeyHandler(trigger: ctrlOpt)
        let signals = Signals()
        handler.onSignal = { signals.add($0) }
        handler.isMouseButtonDown = { mouseDown }
        return (handler, signals)
    }

    /// The ring has no shortcuts of its own: trigger + arrows (or any key) reach the app in front.
    @Test func keysWithTheTriggerPassThrough() async {
        let (handler, signals) = makeHandler()
        #expect(!handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt)))
        let flags = ctrlOpt.union([.maskSecondaryFn, .maskNumericPad])
        for key in [KeyCode.left, KeyCode.right, KeyCode.up, KeyCode.down, KeyCode.returnKey] {
            #expect(!handler.handle(type: .keyDown, event: keyEvent(key, flags: flags)))
        }
        #expect(!handler.mayShowRing) // the trigger was part of another shortcut: no ring
        _ = handler.handle(type: .flagsChanged, event: flagsEvent([]))
        await drainMainQueue()
        #expect(signals.all == [.triggerDown, .triggerUp(apply: false)])
    }

    @Test func holdingTheTriggerAloneOpensAndAppliesTheRing() async {
        let (handler, signals) = makeHandler()
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(handler.mayShowRing)
        _ = handler.handle(type: .flagsChanged, event: flagsEvent([]))
        await drainMainQueue()
        #expect(signals.all == [.triggerDown, .triggerUp(apply: true)])
    }

    @Test func otherShortcutCancelsRing() async {
        let (handler, signals) = makeHandler()
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(!handler.handle(type: .keyDown, event: keyEvent(KeyCode.a, flags: ctrlOpt)))
        #expect(!handler.mayShowRing)
        _ = handler.handle(type: .flagsChanged, event: flagsEvent([]))
        await drainMainQueue()
        #expect(signals.all == [.triggerDown, .triggerUp(apply: false)])
    }

    @Test func extraModifierCancelsInsteadOfApplying() async {
        let (handler, signals) = makeHandler()
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(handler.mayShowRing)
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt.union(.maskShift)))
        await drainMainQueue()
        #expect(signals.all == [.triggerDown, .triggerUp(apply: false)])
    }

    @Test func mouseDragNeverStartsTheRing() async {
        let (handler, signals) = makeHandler(mouseDown: true)
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(!handler.mayShowRing)
        await drainMainQueue()
        #expect(signals.all.isEmpty)
    }

    @Test func escapeCancelsOnlyWhileRingShows() async {
        let (handler, signals) = makeHandler()
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(!handler.handle(type: .keyDown, event: keyEvent(KeyCode.escape, flags: ctrlOpt)))
        handler.isRingVisible = true
        #expect(handler.handle(type: .keyDown, event: keyEvent(KeyCode.escape, flags: ctrlOpt)))
        await drainMainQueue()
        #expect(signals.all.last == .cancel)
    }

    @Test func resetAfterTapTimeoutCancelsHeldTrigger() async {
        let (handler, signals) = makeHandler()
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        handler.isRingVisible = true
        handler.reset()
        #expect(!handler.mayShowRing && !handler.isRingVisible)
        await drainMainQueue()
        #expect(signals.all == [.triggerDown, .triggerUp(apply: false)])
    }

    @Test func remappedTrigger() {
        let (handler, _) = makeHandler()
        handler.trigger = [.maskCommand, .maskShift]
        _ = handler.handle(type: .flagsChanged, event: flagsEvent(ctrlOpt))
        #expect(!handler.mayShowRing) // ⌃⌥ no longer opens it
        _ = handler.handle(type: .flagsChanged, event: flagsEvent([]))
        _ = handler.handle(type: .flagsChanged, event: flagsEvent([.maskCommand, .maskShift]))
        #expect(handler.mayShowRing)
    }
}

@MainActor
struct WindowRingServiceTests {
    @Test func defaultsAndRemapPersist() {
        let defaults = makeDefaults()
        let service = WindowRingService(defaults: defaults, eventTap: nil, windowManager: WindowManagerService(defaults: defaults))
        #expect(service.trigger == WindowRingService.defaultTrigger)
        #expect(service.triggerDisplay == "⌃⌥")
        service.trigger = [.maskCommand, .maskAlternate]
        service.ringSize = .large
        let reloaded = WindowRingService(defaults: defaults, eventTap: nil, windowManager: WindowManagerService(defaults: defaults))
        #expect(reloaded.trigger == [.maskCommand, .maskAlternate])
        #expect(reloaded.handler.trigger == [.maskCommand, .maskAlternate])
        #expect(reloaded.ringSize == .large)
        reloaded.reset()
        #expect(reloaded.trigger == WindowRingService.defaultTrigger)
    }

    @Test func registersWithTapWhenPermitted() {
        let tap = EventTapService()
        let defaults = makeDefaults()
        let service = WindowRingService(defaults: defaults, eventTap: tap, windowManager: WindowManagerService(defaults: defaults))
        service.handler.isMouseButtonDown = { false }
        let flags: CGEventFlags = [.maskControl, .maskAlternate]
        _ = tap.handle(type: .flagsChanged, event: flagsEvent(flags))
        #expect(!service.handler.mayShowRing) // not registered yet
        service.updatePermission(true)
        _ = tap.handle(type: .flagsChanged, event: flagsEvent([]))
        _ = tap.handle(type: .flagsChanged, event: flagsEvent(flags))
        #expect(service.handler.mayShowRing)
    }
}

@MainActor
struct WindowRingRenderTests {
    /// Writes the ring with a highlighted zone to the temp folder for a visual check.
    @Test func renderRing() throws {
        let defaults = makeDefaults()
        let service = WindowRingService(defaults: defaults, eventTap: nil, windowManager: WindowManagerService(defaults: defaults))
        let view = RingView().environment(service).background(Color(white: 0.2)).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let tiff = try #require(renderer.nsImage?.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        try rep.representation(using: .png, properties: [:])!
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("tully-ring.png"))
    }
}
