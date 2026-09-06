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
    func testPriorityMarkerRendersForMidRangeValue() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-priority", "7"]
        app.launch()

        // The marker Text renders "!" but carries the accessibility label
        // "Low priority" (level.displayName + " priority"), so UI tests match
        // the marker element by that label.
        XCTAssertTrue(
            app.staticTexts["priorityMarker"].waitForExistence(timeout: 5),
            "Priority-7 reminder should render the low-priority marker")
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
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
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
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 10),
            "Receiving an exclusion context should hide the card live")
    }

    // MARK: - Complete

    @MainActor
    func testCompleteRemovesReminder() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let complete = app.buttons["completeButton"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3), "Complete button should be present")
        complete.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Completing the only reminder should show the No Reminders state")
    }

    // MARK: - Skip

    @MainActor
    func testSkipShowsAllDoneState() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let skip = app.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skip button should be present")
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Skipping the only reminder should show the All Done state")
    }

    // MARK: - Action menu (toggle synced ON via --ui-testing-action-menu)

    /// Toggle ON: the Skip tap presents the three-action menu instead of
    /// skipping directly; choosing Skip advances the card.
    @MainActor
    func testActionMenuShowsWhenToggleSyncedOn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-action-menu"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let skip = app.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skip button should be present")
        skip.tap()

        // watchOS dialog actions expose their label, not the identifier.
        let dialogSkip = app.buttons["Skip"]
        XCTAssertTrue(
            dialogSkip.waitForExistence(timeout: 3),
            "Toggle ON: Skip should present the action menu, not skip directly")
        dialogSkip.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "The menu's Skip should advance to the All Done state")
    }

    /// Toggle ON: the menu's Delete removes the reminder.
    @MainActor
    func testActionMenuDeleteRemovesWhenToggleSyncedOn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-action-menu"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let skip = app.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let delete = app.buttons["Delete"]
        XCTAssertTrue(
            delete.waitForExistence(timeout: 3),
            "The action menu should offer Delete")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Deleting the only reminder should show the empty state")
    }

    /// Toggle ON: the menu's Reschedule opens the date-picker sheet; confirming
    /// fires the watch→phone reschedule relay and dismisses the sheet with the
    /// card still on screen.
    @MainActor
    func testActionMenuReschedulePresentsSheetWhenToggleSyncedOn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-action-menu"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let skip = app.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let reschedule = app.buttons["Reschedule"]
        XCTAssertTrue(
            reschedule.waitForExistence(timeout: 3),
            "The action menu should offer Reschedule")
        reschedule.tap()

        let confirm = app.buttons["rescheduleConfirmButton"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 3),
            "Reschedule should open the date-picker sheet")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "After confirming the relay, the card stays on screen")
    }

    // MARK: - Skip nudge

    @MainActor
    func testSkipNudgeShowsDeleteDialog() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-skip-count", "5"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // The 6th skip (seed 5 → 6) interrupts the cycle instead of advancing:
        // the card stays put and the nudge banner appears.
        let skip = app.buttons["skipButton"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skip button should be present")
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 3),
            "The 6th skip should keep the reminder visible (interrupt, not advance)")
        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 3),
            "Crossing the 6-skip threshold should show the nudge banner")
        banner.tap()

        // watchOS dialog actions expose their label, not the identifier, so match
        // the destructive Delete action by its label (see the flows delete test).
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Nudge dialog should show Delete")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Deleting the nudged reminder should show the empty state")
    }

    // MARK: - Refresh

    @MainActor
    func testRefreshPresentOnNoRemindersState() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the only reminder to reach the No Reminders state, which
        // presents a Refresh button.
        let complete = app.buttons["completeButton"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["refreshButton"].waitForExistence(timeout: 3),
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
        let upgradeText = app.staticTexts["upgradePrompt"]
        XCTAssertTrue(
            upgradeText.waitForExistence(timeout: 5),
            "Watch should show upgrade prompt when gated")
        XCTAssertFalse(
            app.buttons["completeButton"].exists,
            "Action buttons should be replaced by the upgrade prompt")
    }

    @MainActor
    func testCompleteHoldsCardDuringGlow() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-glow"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        let complete = app.buttons["completeButton"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // Card must stay visible during the glow (2 s glow + 0.5 s buffer = 2.5 s).
        // Assert the card text is still present immediately after the tap —
        // it must NOT disappear in under 1 s.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 1),
            "Card should persist during the post-completion glow")

        // Glow overlay must be present. waitForExistence polls at ~1 s cadence,
        // so a second wait here would not poll until the glow's 2.0 s window has
        // already closed; a direct existence query lands while the glow is still
        // active and the ghost card is still being held.
        XCTAssertTrue(
            app.otherElements["completionGlowOverlay"].exists,
            "Glow overlay should be present while the card is held")

        // After the full delay (2.0 + 0.5 = 2.5 s), the empty state must appear.
        // Generous timeout accounts for CI executor variance.
        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 8),
            "After the glow fades, the No Reminders state should appear")
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
