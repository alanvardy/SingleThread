import XCTest

final class SingleThreadWatchUITestsFlows: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }

    // MARK: - View

    @MainActor
    func testCardShowsReminderTitleAndNotes() {
        let app = launchApp()

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Seeded reminder card should show its title")
        XCTAssertTrue(
            app.staticTexts["Don't forget the milk"].waitForExistence(timeout: 3),
            "Seeded reminder card should show its notes")
    }

    // MARK: - Complete

    @MainActor
    func testCompleteRemovesReminder() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3), "Complete button should be present")
        complete.tap()

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Completing the only reminder should show the No Reminders state")
    }

    // MARK: - Skip

    @MainActor
    func testSkipShowsAllDoneState() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let skip = app.buttons["Skip reminder"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skip button should be present")
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: 5),
            "Skipping the only reminder should show the All Done state")
    }

    // MARK: - Delete (via confirmation dialog)

    @MainActor
    func testDeleteViaConfirmationDialogRemovesReminder() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Tapping the card reveals the confirmation dialog with a Delete action.
        app.staticTexts["Buy groceries"].tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Long-press dialog should show Delete")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Deleting the only reminder should show the No Reminders state")
    }

    // MARK: - Refresh

    @MainActor
    func testRefreshPresentOnNoRemindersState() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the only reminder to reach the No Reminders state, which
        // presents a Refresh button.
        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(app.staticTexts["No Reminders"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Refresh"].waitForExistence(timeout: 3),
            "No Reminders state should offer a Refresh button")
    }
}
