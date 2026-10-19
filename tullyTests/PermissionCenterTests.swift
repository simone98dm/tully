import Testing
@testable import tully

@MainActor
struct PermissionCenterTests {
    final class Flags {
        var accessibility = false
        var screen = false
    }

    @Test func notifiesOnGrantAndRevoke() {
        let flags = Flags()
        let center = PermissionCenter(checker: .init(accessibility: { flags.accessibility }, screenRecording: { flags.screen }))
        var seen: [Bool] = []
        center.observe { seen.append($0.isAccessibilityGranted) }
        #expect(seen == [false])

        center.refresh() // nothing changed
        #expect(seen == [false])

        flags.accessibility = true
        center.refresh()
        #expect(seen == [false, true])
        #expect(!center.allGranted)

        flags.screen = true
        center.refresh()
        #expect(center.allGranted)

        flags.accessibility = false
        center.refresh()
        #expect(seen.last == false)
    }
}
