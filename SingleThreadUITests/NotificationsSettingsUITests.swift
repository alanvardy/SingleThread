import XCTest

final class NotificationsSettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(seedJSON: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", seedJSON]
        app.launch()
        return app
    }

    @MainActor
    func testNotificationsToggleExists() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)

        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // The Notifications row should be visible in the Settings list.
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 3))
        app.staticTexts["Notifications"].tap()

        // The toggle should exist and default to OFF.
        let toggle = app.switches["Enable reminder notifications"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0", "Notifications should default to off")
    }

    @MainActor
    func testIntervalPickerOptions() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)

        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()

        // Tap the picker to reveal options. The menu-style picker button's
        // label combines the title and the current value (e.g. "Remind after,
        // 48 hours"), so match with a prefix predicate.
        let picker = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Remind after"))
            .firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()

        XCTAssertTrue(app.buttons["24 hours"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["48 hours"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["72 hours"].waitForExistence(timeout: 2))
    }
}
