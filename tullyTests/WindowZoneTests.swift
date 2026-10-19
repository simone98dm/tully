import AppKit
import Testing
@testable import tully

struct WindowZoneTests {
    // visible frame of a screen with a 25 pt menu bar and a 70 pt dock, offset like a secondary display
    let visible = CGRect(x: 1440, y: 70, width: 1200, height: 805)

    @Test(arguments: WindowZone.allCases)
    func frameStaysInsideVisibleFrame(zone: WindowZone) {
        let frame = zone.frame(in: visible)
        #expect(visible.contains(frame))
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test func halvesSplitTheScreen() {
        #expect(WindowZone.leftHalf.frame(in: visible) == CGRect(x: 1440, y: 70, width: 600, height: 805))
        #expect(WindowZone.rightHalf.frame(in: visible) == CGRect(x: 2040, y: 70, width: 600, height: 805))
        #expect(WindowZone.topHalf.frame(in: visible) == CGRect(x: 1440, y: 472.5, width: 1200, height: 402.5))
        #expect(WindowZone.bottomHalf.frame(in: visible) == CGRect(x: 1440, y: 70, width: 1200, height: 402.5))
    }

    @Test func thirdsTileWithoutGaps() {
        let left = WindowZone.leftThird.frame(in: visible)
        let center = WindowZone.centerThird.frame(in: visible)
        let right = WindowZone.rightThird.frame(in: visible)
        #expect(left.maxX == center.minX)
        #expect(center.maxX == right.minX)
        #expect(right.maxX == visible.maxX)
        #expect(WindowZone.leftTwoThirds.frame(in: visible).maxX == center.maxX)
        #expect(WindowZone.rightTwoThirds.frame(in: visible).minX == left.maxX)
    }

    @Test func quartersUseAppKitOrientation() {
        // AppKit y grows upward: "top" quarters start at midY
        #expect(WindowZone.topLeft.frame(in: visible).minY == visible.midY)
        #expect(WindowZone.bottomRight.frame(in: visible).minY == visible.minY)
        #expect(WindowZone.topRight.frame(in: visible).minX == visible.midX)
    }

    @Test func fullscreenFillsVisibleFrame() {
        #expect(WindowZone.fullscreen.frame(in: visible) == visible)
    }

    @Test(arguments: WindowZone.allCases)
    func symbolExists(zone: WindowZone) {
        #expect(NSImage(systemSymbolName: zone.symbol, accessibilityDescription: nil) != nil, "missing \(zone.symbol)")
    }

    @Test func rawValuesAreStable() {
        // persisted shortcuts are keyed by rawValue
        #expect(WindowZone.leftHalf.rawValue == "leftHalf")
        #expect(WindowZone.bottomRight.rawValue == "bottomRight")
    }
}
