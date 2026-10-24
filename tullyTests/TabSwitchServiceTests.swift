import CoreGraphics
import Testing
@testable import tully

@MainActor
struct TabSwitchServiceTests {
    func windows(_ count: Int) -> [WindowInfo] {
        (0..<count).map { WindowInfo(id: CGWindowID($0 + 1), appName: "App \($0)", windowTitle: "", pid: 1) }
    }

    @Test func cyclesForwardAndBackWithWrap() {
        let service = TabSwitchService(defaults: makeDefaults())
        service.showOverlay(with: windows(3))
        #expect(service.selectedIndex == 1) // starts on the previous window
        service.cycleSelection(reverse: false)
        #expect(service.selectedIndex == 2)
        service.cycleSelection(reverse: false)
        #expect(service.selectedIndex == 0)
        service.cycleSelection(reverse: true)
        #expect(service.selectedIndex == 2)
        service.dismissOverlay()
        #expect(service.windows.isEmpty)
    }

    @Test func singleAndEmptyLists() {
        let service = TabSwitchService(defaults: makeDefaults())
        service.showOverlay(with: windows(1))
        #expect(service.selectedIndex == 0)
        service.showOverlay(with: [])
        service.cycleSelection(reverse: false)
        #expect(service.selectedIndex == 0)
    }

    @Test func quitDropsAllWindowsOfSelectedApp() {
        let service = TabSwitchService(defaults: makeDefaults())
        let list = [(1, 10), (2, 20), (3, 10), (4, 30)].map {
            WindowInfo(id: CGWindowID($0.0), appName: "", windowTitle: "", pid: pid_t($0.1))
        }
        service.showOverlay(with: list)
        service.cycleSelection(reverse: false) // window 3, pid 10
        var quit: [pid_t] = []
        service.quitSelectedApp { quit.append($0) }
        #expect(quit == [10])
        #expect(service.windows.map(\.id) == [2, 4])
        #expect(service.selectedIndex == 1) // the window after the quit one
        service.quitSelectedApp { quit.append($0) }
        service.quitSelectedApp { quit.append($0) }
        #expect(quit == [10, 30, 20])
        #expect(service.windows.isEmpty) // last app quit closes the overlay
    }

    @Test func quitNeverTargetsTullyItself() {
        let service = TabSwitchService(defaults: makeDefaults())
        let own = getpid()
        service.showOverlay(with: [WindowInfo(id: 1, appName: "", windowTitle: "", pid: own)])
        service.quitSelectedApp { _ in Issue.record("must not terminate itself") }
        #expect(service.windows.count == 1)
    }

    @Test func persistsEnabledAndHotkey() {
        let defaults = makeDefaults()
        let hotkey = ShortcutBinding(keyCode: KeyCode.space, modifiers: CGEventFlags.maskAlternate.rawValue)
        let service = TabSwitchService(defaults: defaults)
        service.setEnabled(true)
        service.setHotkey(hotkey)
        let reloaded = TabSwitchService(defaults: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.hotkey == hotkey)
        reloaded.reset()
        #expect(!TabSwitchService(defaults: defaults).isEnabled)
    }

    @Test func listensOnlyWhenEnabledWithHotkeyAndPermission() {
        let tap = EventTapService()
        let service = TabSwitchService(defaults: makeDefaults(), eventTap: tap)
        let event = keyEvent(KeyCode.space, flags: .maskAlternate)
        service.setHotkey(ShortcutBinding(keyCode: KeyCode.space, modifiers: CGEventFlags.maskAlternate.rawValue))
        service.setEnabled(true)
        #expect(!tap.handle(type: .keyDown, event: event)) // no permission yet
        service.updatePermissions(accessibility: true, screenRecording: false)
        #expect(tap.handle(type: .keyDown, event: event))
        service.setEnabled(false)
        #expect(!tap.handle(type: .keyDown, event: event))
    }
}
