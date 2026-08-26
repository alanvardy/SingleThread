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

        // Navigate into the Interface sub-view.
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3), "Settings should show Interface")
        app.staticTexts["Interface"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Text Size"].waitForExistence(timeout: 2))

        // Back to root, then into Reminder.
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Reminder"].tap()
        XCTAssertTrue(app.staticTexts["Show date"].waitForExistence(timeout: 2))

        // Back to root, then into Filtering & Sorting.
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Filtering & Sorting"].tap()
        XCTAssertTrue(app.staticTexts["Sort By"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Excluded Lists"].waitForExistence(timeout: 2))
    }

    // MARK: - Background toggle

    @MainActor
    func testBackgroundToggleHidesAndPersistsAcrossRelaunch() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.staticTexts["Background"].waitForExistence(timeout: 3), "Settings should show Background")
        app.staticTexts["Background"].tap()
        let toggle = app.switches["Background"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "Background should default to on")
        XCTAssertTrue(flipToggle(toggle), "Tapping should hide the background")

        // The done button lives on the settings root, so pop back to it first.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()

        // A relaunch with `--seed` would call `resetPersistedState()` and wipe
        // the very key under test, so persistence is verified via a second
        // `--ui-testing` launch, which does not reset `.standard` defaults.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.staticTexts["Background"].tap()
        let persistedToggle = relaunched.switches["Background"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedToggle.value as? String, "0",
            "Background-off should persist across relaunch")
    }

    // MARK: - Show list toggle

    /// Uses `--ui-testing` (not `--seed`) for both launches: seeding calls
    /// `resetPersistedState()` and would wipe the key under test.
    @MainActor
    func testShowListTogglePersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.buttons["Settings"].tap()

        // Navigate into the Reminder sub-view.
        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3), "Settings should show Reminder")
        app.staticTexts["Reminder"].tap()
        let toggle = app.switches["Show list"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0", "Show list should default to off")
        XCTAssertTrue(flipToggle(toggle, target: "1"), "Tapping should enable Show list")

        // The done button lives on the settings root, so pop back to it first.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.staticTexts["Reminder"].tap()
        let persistedToggle = relaunched.switches["Show list"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedToggle.value as? String, "1",
            "Show-list-on should persist across relaunch")
    }

    /// SwiftUI Form rows expose a nested switch control; tapping the outer row
    /// element is swallowed, so tap the inner control until it flips. In the
    /// pushed sub-view the switch itself is the control (no nested `switches`
    /// child), so fall back to tapping the outer element directly.
    @MainActor
    private func flipToggle(_ toggle: XCUIElement, target: String = "0") -> Bool {
        let inner = toggle.switches.firstMatch
        let tapTarget = inner.exists ? inner : toggle
        for _ in 0..<3 {
            if toggle.value as? String == target { return true }
            tapTarget.tap()
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if toggle.value as? String == target { return true }
                usleep(100_000)
            }
        }
        return toggle.value as? String == target
    }
}
