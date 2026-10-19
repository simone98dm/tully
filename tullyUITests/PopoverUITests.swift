import XCTest

final class PopoverUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--open-popover-window"] + extra
        app.launch()
        return app
    }

    func testAllTabsAreReachable() {
        let app = launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for title in ["System", "Disk", "Windows", "Switcher", "Convert"] {
            let tab = window.buttons[title]
            XCTAssertTrue(tab.exists, "missing tab \(title)")
            tab.click()
        }
    }

    func testCommandNumberSwitchesTabs() {
        let app = launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(window.staticTexts["Accessibility Required"].waitForExistence(timeout: 3))
        window.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(window.staticTexts["Large Folders"].waitForExistence(timeout: 3))
    }

    func testGearOpensSettingsWindow() {
        let app = launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["Settings"].click()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 5))
    }

    func testConverterToggleSwitchesState() {
        let app = launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.buttons["Convert"].click()
        let toggle = window.descendants(matching: .any)["Enable File Converter"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertEqual("\(toggle.value ?? "")", "1") // on by default
        toggle.click()
        XCTAssertTrue(window.buttons["Turn On"].waitForExistence(timeout: 3))
        window.buttons["Turn On"].click()
        XCTAssertEqual("\(toggle.value ?? "")", "1")
    }

    func testTabStateSurvivesSwitching() {
        let app = launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        window.typeKey("2", modifierFlags: .command)
        window.buttons["Scan Home Folder"].click()
        window.typeKey("1", modifierFlags: .command)
        window.typeKey("2", modifierFlags: .command)
        // the scan started on the Disk tab is still there (kept alive), not reset to the empty state
        XCTAssertFalse(window.buttons["Scan Home Folder"].exists)
    }
}
