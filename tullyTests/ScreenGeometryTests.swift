import CoreGraphics
import Testing
@testable import tully

struct ScreenGeometryTests {
    // Primary 1440×900 at origin; secondary 1920×1080 to the right, raised 200 pt.
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let rightRaised = CGRect(x: 1440, y: 200, width: 1920, height: 1080)
    // Display stacked above the primary.
    let above = CGRect(x: 0, y: 900, width: 1440, height: 900)

    @Test func flipsAXRectToAppKit() {
        let ax = CGRect(x: 100, y: 50, width: 400, height: 300)
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryHeight: 900)
        #expect(appKit == CGRect(x: 100, y: 550, width: 400, height: 300))
    }

    @Test func axOriginRoundTrips() {
        let appKit = CGRect(x: 1500, y: 300, width: 800, height: 600)
        let origin = ScreenGeometry.axOrigin(forAppKit: appKit, primaryHeight: 900)
        let back = ScreenGeometry.appKitRect(fromAX: CGRect(origin: origin, size: appKit.size), primaryHeight: 900)
        #expect(back == appKit)
    }

    @Test func picksScreenWithLargestOverlap() {
        // mostly on the secondary, slightly on the primary
        let window = CGRect(x: 1300, y: 300, width: 800, height: 500)
        #expect(ScreenGeometry.bestScreenIndex(for: window, screens: [primary, rightRaised]) == 1)
    }

    /// Regression for B2: an AX window on the screen above the primary has a negative AX y.
    /// The old code tested the raw AX point against AppKit frames and picked the primary.
    @Test func windowOnScreenAbovePrimaryIsDetected() {
        let ax = CGRect(x: 200, y: -700, width: 600, height: 400) // top-left coordinates
        let appKit = ScreenGeometry.appKitRect(fromAX: ax, primaryHeight: primary.height)
        #expect(ScreenGeometry.bestScreenIndex(for: appKit, screens: [primary, above]) == 1)
    }

    @Test func offscreenWindowFallsBackToNearestScreen() {
        let window = CGRect(x: 5000, y: 400, width: 100, height: 100)
        #expect(ScreenGeometry.bestScreenIndex(for: window, screens: [primary, rightRaised]) == 1)
    }

    @Test func noScreensGivesNil() {
        #expect(ScreenGeometry.bestScreenIndex(for: .zero, screens: []) == nil)
    }

    @Test func pointLookupUsesContainingScreen() {
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: 2000, y: 500), screens: [primary, rightRaised]) == 1)
        #expect(ScreenGeometry.screenIndex(containing: CGPoint(x: 10, y: 10), screens: [primary, rightRaised]) == 0)
    }
}
