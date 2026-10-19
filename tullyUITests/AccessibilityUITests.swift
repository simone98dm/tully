import XCTest

/// Every control a user can act on must have a name VoiceOver can read.
final class AccessibilityUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    private func unlabeled(in element: XCUIElement) -> [String] {
        let types: [XCUIElement.ElementType] = [.button, .checkBox, .switch, .slider, .popUpButton, .menuButton, .radioButton]
        return types.flatMap { type in
            element.descendants(matching: type).allElementsBoundByIndex.compactMap { control in
                // window traffic-light buttons are AppKit's, not ours
                guard control.exists, control.isHittable, !control.identifier.hasPrefix("_XCUI") else { return nil }
                let name = control.label.isEmpty ? control.title : control.label
                return name.trimmingCharacters(in: .whitespaces).isEmpty ? "\(type.rawValue) \(control.frame)" : nil
            }
        }
    }

    func testPopoverTabsHaveLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--open-popover-window"]
        app.launch()
        let window = app.windows["tully"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for tab in ["System", "Disk", "Windows", "Switcher", "Convert"] {
            window.buttons[tab].click()
            XCTAssertEqual(unlabeled(in: window), [], "unlabelled controls on \(tab)")
        }
    }

    func testSettingsPanesHaveLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--open-settings=general"]
        app.launch()
        let window = app.windows["settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        for pane in ["General", "Menu Bar", "Window Manager", "Window Ring", "Window Switcher", "File Converter",
                     "Disk Clean", "Power & Keyboard", "About & Help"] {
            window.outlines.staticTexts[pane].click()
            XCTAssertEqual(unlabeled(in: window), [], "unlabelled controls in \(pane)")
        }
    }

    func testDiskCleanAndMonitorHaveLabels() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--open-disk-clean", "--open-system-monitor"]
        app.launch()
        for id in ["diskClean", "systemMonitor"] {
            let window = app.windows[id]
            XCTAssertTrue(window.waitForExistence(timeout: 10))
            XCTAssertEqual(unlabeled(in: window), [], "unlabelled controls in \(id)")
        }
    }
}
