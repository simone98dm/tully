import CoreGraphics
import Foundation
import Testing
@testable import tully

@MainActor
struct WindowManagerServiceTests {
    let binding = ShortcutBinding(keyCode: KeyCode.left, modifiers: CGEventFlags([.maskControl, .maskAlternate]).rawValue)

    @Test func persistsShortcuts() {
        let defaults = makeDefaults()
        WindowManagerService(defaults: defaults).setShortcut(binding, for: .leftHalf)
        #expect(WindowManagerService(defaults: defaults).shortcuts[WindowZone.leftHalf.rawValue] == binding)
    }

    @Test func clearAndReset() {
        let defaults = makeDefaults()
        let service = WindowManagerService(defaults: defaults)
        service.setShortcut(binding, for: .leftHalf)
        service.setShortcut(binding, for: .rightHalf)
        service.setShortcut(nil, for: .leftHalf)
        #expect(service.shortcuts.keys.sorted() == ["rightHalf"])
        service.reset()
        #expect(service.shortcuts.isEmpty)
        #expect(WindowManagerService(defaults: defaults).shortcuts.isEmpty)
    }

    @Test func detectsConflicts() {
        let service = WindowManagerService(defaults: makeDefaults())
        service.setShortcut(binding, for: .leftHalf)
        #expect(service.conflictingZone(for: binding, excluding: .rightHalf) == .leftHalf)
        #expect(service.conflictingZone(for: binding, excluding: .leftHalf) == nil)
    }

    @Test func migratesLegacyKey() throws {
        let defaults = makeDefaults()
        let legacy = try JSONEncoder().encode(["rightHalf": binding])
        defaults.set(legacy, forKey: WindowManagerService.legacyShortcutsKey)
        let service = WindowManagerService(defaults: defaults)
        #expect(service.shortcuts["rightHalf"] == binding)
        #expect(defaults.data(forKey: WindowManagerService.legacyShortcutsKey) != nil) // older versions keep working
        #expect(defaults.data(forKey: WindowManagerService.shortcutsKey) != nil)
    }

    @Test func registersWithTapOnlyWhenPermitted() {
        let tap = EventTapService()
        let service = WindowManagerService(defaults: makeDefaults(), eventTap: tap)
        service.setShortcut(binding, for: .leftHalf)
        let event = keyEvent(KeyCode.left, flags: [.maskControl, .maskAlternate])
        #expect(!tap.handle(type: .keyDown, event: event))
        service.updatePermission(true)
        #expect(tap.handle(type: .keyDown, event: event))
        service.updatePermission(false)
        #expect(!tap.handle(type: .keyDown, event: event))
    }
}

@MainActor
struct AutoLayoutTests {
    // primary 1000 pt tall; AX (top-left) frames
    func window(_ id: CGWindowID, x: CGFloat, y: CGFloat) -> WindowInfo {
        WindowInfo(id: id, appName: "App \(id)", windowTitle: "", pid: 1, frame: CGRect(x: x, y: y, width: 400, height: 300))
    }

    @Test func candidatesExcludeSnappedAndOtherScreens() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let windows = [window(1, x: 10, y: 10), window(2, x: 500, y: 200), window(3, x: 2000, y: 100)]
        let result = AutoLayoutController.candidates(from: windows, excluding: 1, on: screen, primaryHeight: 1000)
        #expect(result.map(\.id) == [2])
    }

    @Test func takenSpaceIsNotOffered() {
        let left = CGRect(x: 0, y: 0, width: 800, height: 1000)
        #expect(AutoLayoutController.isFree(left, avoiding: []))
        #expect(AutoLayoutController.isFree(left, avoiding: [CGRect(x: 600, y: 0, width: 400, height: 300)])) // small overlap
        #expect(!AutoLayoutController.isFree(left, avoiding: [CGRect(x: 0, y: 0, width: 800, height: 1000)]))  // tiled there
        #expect(!AutoLayoutController.isFree(left, avoiding: [CGRect(x: 4, y: 0, width: 790, height: 990)]))   // tiled, with a gap
        // a maximized window behind both halves doesn't make the half "taken"
        #expect(AutoLayoutController.isFree(left, avoiding: [CGRect(x: 0, y: 0, width: 1600, height: 1000)]))
        #expect(!AutoLayoutController.isFree(.zero, avoiding: []))
    }

    @Test func candidatesAreCapped() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let windows = (1...20).map { window(CGWindowID($0), x: 10, y: 10) }
        #expect(AutoLayoutController.candidates(from: windows, excluding: nil, on: screen, primaryHeight: 1000).count
                == AutoLayoutController.maxCandidates)
    }

    @Test func keyboardHighlightWrapsAndDismissClears() {
        let controller = AutoLayoutController(eventTap: nil)
        controller.present([window(1, x: 0, y: 0), window(2, x: 0, y: 0)], in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(controller.isVisible && controller.highlighted == 0)
        controller.moveHighlight(by: -1)
        #expect(controller.highlighted == 1)
        controller.moveHighlight(by: 1)
        #expect(controller.highlighted == 0)
        controller.dismiss()
        #expect(!controller.isVisible)
    }

    @Test func autoLayoutSettingsPersist() {
        let defaults = makeDefaults()
        let service = WindowManagerService(defaults: defaults)
        #expect(service.isAutoLayoutEnabled && service.autoLayoutDelay == 6)
        service.isAutoLayoutEnabled = false
        service.autoLayoutDelay = 10
        let reloaded = WindowManagerService(defaults: defaults)
        #expect(!reloaded.isAutoLayoutEnabled && reloaded.autoLayoutDelay == 10)
        reloaded.reset()
        #expect(reloaded.isAutoLayoutEnabled)
    }

    @Test func autoLayoutKeysAreConsumedOnlyWhileVisible() {
        let tap = EventTapService()
        let controller = AutoLayoutController(eventTap: tap)
        #expect(!tap.handle(type: .keyDown, event: keyEvent(KeyCode.down)))
        controller.present([window(1, x: 0, y: 0)], in: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(tap.handle(type: .keyDown, event: keyEvent(KeyCode.down)))
        #expect(!tap.handle(type: .keyDown, event: keyEvent(KeyCode.a)))
        // modified keys belong to the frontmost app
        #expect(!tap.handle(type: .keyDown, event: keyEvent(KeyCode.up, flags: .maskCommand)))
        controller.dismiss()
        #expect(!tap.handle(type: .keyDown, event: keyEvent(KeyCode.down)))
    }
}
