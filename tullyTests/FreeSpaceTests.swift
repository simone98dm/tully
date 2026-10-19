import CoreGraphics
import Testing
@testable import tully

struct FreeSpaceTests {
    let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    let left = CGRect(x: 0, y: 0, width: 500, height: 1000)
    let right = CGRect(x: 1100, y: 0, width: 500, height: 1000)

    @Test func emptyScreenIsAllFree() {
        #expect(FreeSpace.rect(containing: CGPoint(x: 800, y: 500), in: screen, avoiding: []) == screen)
    }

    @Test func gapBetweenTwoWindows() {
        #expect(FreeSpace.rect(containing: CGPoint(x: 800, y: 500), in: screen, avoiding: [left, right])
                == CGRect(x: 500, y: 0, width: 600, height: 1000))
    }

    @Test func coveredPointHasNoSpace() {
        #expect(FreeSpace.rect(containing: CGPoint(x: 100, y: 500), in: screen, avoiding: [left]) == nil)
    }

    @Test func keepsTheLargerSideOfACornerWindow() {
        let corner = CGRect(x: 1200, y: 600, width: 400, height: 400)
        #expect(FreeSpace.rect(containing: CGPoint(x: 600, y: 500), in: screen, avoiding: [corner])
                == CGRect(x: 0, y: 0, width: 1200, height: 1000))
    }

    @Test func tooSmallGapIsIgnored() {
        let nearlyFull = CGRect(x: 0, y: 0, width: 1500, height: 1000)
        #expect(FreeSpace.rect(containing: CGPoint(x: 1550, y: 500), in: screen, avoiding: [nearlyFull]) == nil)
    }

    @Test func freeQuadrant() {
        let tl = CGRect(x: 0, y: 500, width: 800, height: 500)
        let tr = CGRect(x: 800, y: 500, width: 800, height: 500)
        let bl = CGRect(x: 0, y: 0, width: 800, height: 500)
        #expect(FreeSpace.rect(containing: CGPoint(x: 1200, y: 250), in: screen, avoiding: [tl, tr, bl])
                == CGRect(x: 800, y: 0, width: 800, height: 500))
    }

    @Test func remainderBesideSideSnaps() {
        #expect(FreeSpace.remainder(after: CGRect(x: 0, y: 0, width: 800, height: 1000), in: screen)
                == CGRect(x: 800, y: 0, width: 800, height: 1000))
        #expect(FreeSpace.remainder(after: CGRect(x: 0, y: 0, width: 1600 / 3, height: 1000), in: screen)
                == CGRect(x: 1600 / 3, y: 0, width: 1600 - 1600 / 3, height: 1000))
        #expect(FreeSpace.remainder(after: CGRect(x: 0, y: 500, width: 1600, height: 500), in: screen)
                == CGRect(x: 0, y: 0, width: 1600, height: 500))
    }

    @Test func noRemainderForQuartersOrFullscreen() {
        #expect(FreeSpace.remainder(after: CGRect(x: 0, y: 500, width: 800, height: 500), in: screen) == nil)
        #expect(FreeSpace.remainder(after: screen, in: screen) == nil)
    }

    /// Every side zone leaves space the suggestions can fill; corners and fullscreen don't.
    @Test(arguments: WindowZone.allCases)
    func zoneRemainders(zone: WindowZone) {
        let remainder = FreeSpace.remainder(after: zone.frame(in: screen), in: screen)
        let offersSpace: Set<WindowZone> = [.leftHalf, .rightHalf, .topHalf, .bottomHalf, .leftThird, .rightThird,
                                            .leftTwoThirds, .rightTwoThirds, .centerThird]
        #expect((remainder != nil) == offersSpace.contains(zone))
    }
}
