import XCTest

final class WindowsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ flags: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + flags
        app.launch()
        return app
    }

    func testDiskTabOpensDiskClean() {
        let app = launch(["--open-popover-window"])
        let popover = app.windows["tully"]
        XCTAssertTrue(popover.waitForExistence(timeout: 10))
        popover.buttons["Disk"].click()
        popover.buttons["Clean Up…"].click()
        let window = app.windows["diskClean"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["Scan"].exists)
        XCTAssertTrue(window.buttons["Move to Trash…"].exists)
        XCTAssertTrue(window.checkBoxes["Clean User Caches"].exists)
    }

    func testSystemMonitorOpensFromRing() {
        let app = launch(["--open-popover-window"])
        let popover = app.windows["tully"]
        XCTAssertTrue(popover.waitForExistence(timeout: 10))
        popover.buttons["All Processes"].click()
        let window = app.windows["systemMonitor"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.textFields["Search processes"].exists)
    }

    func testQuickTogglesAreLabelled() {
        let app = launch(["--open-popover-window"])
        let popover = app.windows["tully"]
        XCTAssertTrue(popover.waitForExistence(timeout: 10))
        let stayAwake = popover.descendants(matching: .any)["Stay Awake"].firstMatch
        XCTAssertTrue(stayAwake.exists)
        let before = "\(stayAwake.value ?? "")"
        stayAwake.click()
        XCTAssertNotEqual("\(stayAwake.value ?? "")", before)
        stayAwake.click()
        XCTAssertTrue(popover.descendants(matching: .any)["Keyboard Clean"].firstMatch.exists)
    }

    func testAboutWindowShowsVersionAndLinks() {
        let app = launch(["--open-about"])
        let window = app.windows["about"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["tully"].exists)
        XCTAssertTrue(window.descendants(matching: .any)["GitHub"].firstMatch.exists)
        XCTAssertTrue(window.descendants(matching: .any)["Report a Problem"].firstMatch.exists)
        window.buttons["Settings"].click()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 5))
    }
}
