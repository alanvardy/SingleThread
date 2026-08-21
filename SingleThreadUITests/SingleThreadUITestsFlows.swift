//
//  SingleThreadUITestsFlows.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-20.
//
//  User-use-case UI tests driven by the `--seed '<json>'` launch-arg seam,
//  which backs the app with an in-memory EventKit store so complete/delete/skip
//  mutate deterministically without touching a real EKEventStore.
//

import XCTest

final class SingleThreadUITestsFlows: XCTestCase {

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

    // MARK: - List rendering

    @MainActor
    func testListShowsSeededReminder() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries","notes":"milk"}]}"#)

        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Seeded reminder title should be displayed")
        XCTAssertTrue(
            app.staticTexts["milk"].waitForExistence(timeout: 2),
            "Seeded reminder notes should be displayed on the card")
    }

    @MainActor
    func testEmptyListShowsNoRemindersState() {
        let app = launchApp(seedJSON: #"{"reminders":[]}"#)

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Empty seeded store should render the No Reminders empty state")
    }

    // MARK: - Skip

    @MainActor
    func testSkipAdvancesToNextReminder() {
        // "First" (high priority) sorts before "Second" (low priority).
        let seed = #"{"reminders":[{"title":"First","priority":1},{"title":"Second","priority":9}]}"#
        let app = launchApp(seedJSON: seed)

        let first = app.staticTexts["First"]
        XCTAssertTrue(first.waitForExistence(timeout: 5), "Highest-priority reminder should be shown first")
        first.swipeUp()
        // Skip via the trailing swipe action.
        app.staticTexts["First"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skipping should reveal the Skip swipe action")
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["Second"].waitForExistence(timeout: 5),
            "After skipping the first reminder, the next should be shown")
    }

    @MainActor
    func testSkipAllShowsAllDoneState() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Only one"}]}"#)

        XCTAssertTrue(app.staticTexts["Only one"].waitForExistence(timeout: 5))
        app.staticTexts["Only one"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: 5),
            "Skipping the only reminder should show the All Done state")
    }

    // MARK: - Complete

    @MainActor
    func testCompleteViaSwipeRemovesReminder() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        // Complete is the leading swipe action (reveal by swiping right).
        app.staticTexts["Buy groceries"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3), "Completing should reveal the Complete swipe action")
        complete.tap()

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Completing the only reminder should empty the list")
    }

    // MARK: - Delete

    @MainActor
    func testDeleteViaContextMenuRemovesReminder() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy groceries"].press(forDuration: 1.0)

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Long-press should reveal the Delete context action")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["No Reminders"].waitForExistence(timeout: 5),
            "Deleting the only reminder should empty the list")
    }

    // MARK: - Settings

    @MainActor
    func testSettingsOpensAndShowsControls() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3), "Settings should show Appearance")
        XCTAssertTrue(app.staticTexts["Text Size"].waitForExistence(timeout: 2), "Settings should show Text Size")
        XCTAssertTrue(app.staticTexts["Sort By"].waitForExistence(timeout: 2), "Settings should show Sort By")
        // "Show Date" sits lower in the Form; scroll the sheet to reveal it.
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["Show Date"].waitForExistence(timeout: 3),
            "Settings should show Show Date (after scrolling)")
    }

    // MARK: - Settings descriptions

    /// Every settings row carries a tappable ⓘ (`DescriptionInfoButton`) that
    /// reveals the row's description in a popover. This test drives the full
    /// tap-to-reveal flow end-to-end: open Settings, tap the Appearance row's
    /// info button, and assert the description text is on screen.
    @MainActor
    func testSettingsRowsRenderAndDescriptionsAreAccessible() throws {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // The preference rows render (Appearance / Text Size / Sort By are always
        // visible without scrolling).
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3), "Settings should show Appearance")
        XCTAssertTrue(app.staticTexts["Text Size"].waitForExistence(timeout: 2), "Settings should show Text Size")
        XCTAssertTrue(app.staticTexts["Sort By"].waitForExistence(timeout: 2), "Settings should show Sort By")

        // Tap the Appearance row's ⓘ button and assert the description reveals.
        let appearanceInfoButton = app.buttons["About Appearance"]
        XCTAssertTrue(appearanceInfoButton.waitForExistence(timeout: 2), "Appearance row should show an info button")
        appearanceInfoButton.tap()
        XCTAssertTrue(
            app.staticTexts["Choose System, Light, or Dark styling for the app."].waitForExistence(timeout: 2),
            "Tapping the info button should reveal the description popover")

        // Dismiss the popover, then prove a Toggle row's ⓘ button is also
        // tappable (it sits inside the toggle's label).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let microphoneInfoButton = app.buttons["About Show Microphone"]
        XCTAssertTrue(
            microphoneInfoButton.waitForExistence(timeout: 2),
            "Show Microphone row should show an info button")
        microphoneInfoButton.tap()
        XCTAssertTrue(
            app.staticTexts[
                "Controls whether the dictation microphone appears in the bottom bar."
            ].waitForExistence(timeout: 2),
            "Tapping the toggle row's info button should reveal its description popover")

        // Dismiss the popover, then audit the Settings surface. The audit types
        // are iOS-only, so on macOS run the platform defaults.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        #if os(iOS)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
        #else
            try app.performAccessibilityAudit()
        #endif
    }
}
