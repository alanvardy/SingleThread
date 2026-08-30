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

    // MARK: - Completion glow

    @MainActor
    func testUpgradeOniPhoneShowsWhenGated() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-gated"]
        app.launch()

        // With the counter seeded at the cap and no entitlement synced, the
        // watch must show the iPhone-upgrade prompt instead of action buttons.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Seeded card should render before the gate check")
        let upgradeText = app.staticTexts["Upgrade on\nyour iPhone"]
        XCTAssertTrue(
            upgradeText.waitForExistence(timeout: 5),
            "Watch should show upgrade prompt when gated")
        XCTAssertFalse(
            app.buttons["Complete reminder"].exists,
            "Action buttons should be replaced by the upgrade prompt")
    }

    @MainActor
    func testCompletionGlowDoesNotAppearWhenDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-glow-disabled"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Completing should empty the list")
        XCTAssertFalse(
            app.otherElements["completionGlowOverlay"].exists,
            "Glow should be suppressed when disabled")
    }

    @MainActor
    func testCompletionGlowFlashesWhenEnabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // Glow duration is extended to 2 s under the seam, so `waitForExistence`
        // is deterministic.
        XCTAssertTrue(
            app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3),
            "Glow overlay should flash briefly after completion")
    }

    // MARK: Private

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }
}
