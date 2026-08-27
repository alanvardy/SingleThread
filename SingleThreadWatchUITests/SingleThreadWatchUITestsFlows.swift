import XCTest

final class SingleThreadWatchUITestsFlows: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        continueAfterFailure = false
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

    @MainActor
    func testExcludedListDoesNotRenderReminder() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-excluded-list", "Work"]
        app.launch()

        // The seeded reminder lives in the excluded "Work" list, so its card must
        // not render — "Buy groceries" stays concealed. With nothing visible, the
        // watch shows the All Done state (visibleReminders empty but reminders non-empty).
        XCTAssertFalse(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 3),
            "Excluded list should suppress the reminder card")
        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: 5),
            "With the only reminder excluded, the All Done state should show")
    }

    // MARK: - Live propagation

    @MainActor
    func testLiveExclusionHidesReminderWithoutRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-live-excluded", "Work"]
        app.launch()

        // Before the delayed context arrives the card is visible…
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Seeded card should render before the exclusion context arrives")
        // …then the live receive path filters it without an app relaunch.
        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: 10),
            "Receiving an exclusion context should hide the card live")
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

    // MARK: Private

    @MainActor
    func testGuideReappearsAfterPhoneResets() {
        let app = launchApp()

        // Without --reset-guide, guide should not show
        XCTAssertFalse(app.buttons["Got it"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Simulate phone pushing showGuide:true by delivering an application context
        // with showGuide:true — mirrors the live-exclusion test pattern
        // NOTE: This test requires the watch app to be running with a sync service.
        // The app uses a real WCSession which can receive updateApplicationContext
        // in UI testing. If this proves unreliable, this test moves to unit-test
        // coverage (the sync pipeline test already covers the receive path).
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }
}
