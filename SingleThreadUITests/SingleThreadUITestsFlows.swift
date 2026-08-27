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
    // Shared long-title seeds (also referenced by the accessibility-audit test).
    static let longTitleSeed = #"{"reminders":[{"title":"Remember to buy groceries milk eggs bread butter cheese yogurt cereal coffee tea sugar flour pasta rice apples oranges bananas tomatoes onions potatoes carrots celery lettuce spinach broccoli cauliflower peppers cucumbers squash zucchini garlic ginger olive oil vinegar salt pepper"}]}"#

    static let longCodeSpanSeed = #"{"reminders":[{"title":"Use `map` and `filter` to process the collection of items before rendering them in the list view with `compactMap` and `reduce` to produce the final result set for the grocery run this week"}]}"#

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

    // MARK: - iPad seed launch

    @MainActor
    func testSeedLaunchesOnIPad() {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", #"{"reminders":[{"title":"Buy groceries"}]}"#]

        // Defensive TCC/interruption handler. The seed path backs the app with
        // InMemoryEventStore (.fullAccess, no EventKit access request), so no
        // dialog is expected — but if a system alert appears on iPad, dismiss its
        // primary action before asserting.
        addUIInterruptionMonitor(withDescription: "TCC dialog") { alert -> Bool in
            if alert.buttons.count > 1 {
                alert.buttons.element(boundBy: 1).tap()
            } else {
                alert.buttons.firstMatch.tap()
            }
            return true
        }

        app.launch()
        app.tap() // triggers any pending interruption monitor

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Seeded reminder title should display on iPad without a blocking dialog")
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

        // Back to root, then into Privacy.
        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["Privacy"].tap()
        XCTAssertTrue(
            app.navigationBars["Privacy"].waitForExistence(timeout: 2),
            "Privacy screen should be pushed with its own navigation title")
        XCTAssertTrue(
            app.staticTexts["Skipped & Excluded Lists"].waitForExistence(timeout: 2),
            "Privacy should show its disclosure sections")
    }

    // MARK: - About

    @MainActor
    func testAboutModalShowsAttribution() {
        let app = launchApp(seedJSON: #"{"reminders":[]}"#)

        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // The About row sits at the bottom of the Settings List; scroll if needed.
        let about = app.buttons["About"]
        if !about.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(about.waitForExistence(timeout: 3), "Settings should show an About row")
        about.tap()

        XCTAssertTrue(
            app.staticTexts["Copyright 2026 Alan Vardy"].waitForExistence(timeout: 3),
            "About should show the copyright line")
        XCTAssertTrue(
            app.staticTexts["Made with love by a lone developer"].waitForExistence(timeout: 2),
            "About should show the made-with-love line")
        XCTAssertTrue(
            app.staticTexts["Version 1.0 (1)"].waitForExistence(timeout: 2),
            "About should show the version + build")

        // The `mailto:` link is a tappable `Link`, not a plain `Text`. Assert its
        // presence (as a button OR staticText, whichever the element tree exposes)
        // but NEVER tap it.
        let emailElement = app.buttons["alan@vardy.cc"].exists
            || app.staticTexts["alan@vardy.cc"].waitForExistence(timeout: 2)
        XCTAssertTrue(emailElement, "About should show the feedback email link")
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

    // MARK: - Code blocks

    @MainActor
    func testCodeBlocksRenderWithoutBacktickFences() {
        let seed = #"{"reminders":[{"title":"Use `map`","notes":"```\nlet x = 1\n```"}]}"#
        let app = launchApp(seedJSON: seed)

        // Attributed text with code spans exposes accessibility *labels* but
        // not string identifiers, so the `staticTexts["..."]` subscript lookup
        // (which matches by identifier) fails. Gather all StaticText labels and
        // assert on the aggregated visible text instead.
        let loaded = NSPredicate { _, _ in
            let text = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n")
            return text.contains("map") && text.contains("let x = 1")
        }
        let expectation = XCTNSPredicateExpectation(predicate: loaded, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)

        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let visible = labels.joined(separator: "\n")

        // Backtick fences themselves are NOT part of visible text.
        XCTAssertFalse(visible.contains("`"), "Backtick fences should be stripped, got: \(labels)")

        // Styled code content is visible without the fences.
        XCTAssertTrue(visible.contains("map"), "Inline code span content should be visible, got: \(labels)")
        XCTAssertTrue(visible.contains("let x = 1"), "Fenced code content should be visible, got: \(labels)")
    }

    // MARK: - Long title wrapping

    @MainActor
    func testLongTitleWrapsWithoutClipping() {
        let app = launchApp(seedJSON: Self.longTitleSeed)

        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 5),
            "Seeded card should render before wrapping assertions")

        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let visible = labels.joined(separator: " ")

        // The full title must be present in the aggregated visible text.
        XCTAssertTrue(
            visible.contains("Remember to buy groceries milk eggs bread butter cheese"),
            "Full title should be visible, got: \(labels)")

        // No truncation ellipsis anywhere in the rendered text.
        XCTAssertFalse(
            labels.contains(where: { $0.hasSuffix("…") || $0.hasSuffix("...") }),
            "Title should not be truncated, got: \(labels)")

        // Supplementary clipping check: accessibility labels carry the full string
        // even when text is visually clipped, so label presence alone can't tell a
        // wrapped title from a single-line clipped one. A title this long must span
        // several wrapped lines — assert the title element grew taller than a
        // single `.title` line (~40pt).
        guard let titleElement = app.staticTexts
            .allElementsBoundByIndex
            .first(where: { $0.label.contains("Remember to buy groceries") })
        else {
            return XCTFail("Title element should be present")
        }
        XCTAssertGreaterThan(
            titleElement.frame.height, 60,
            "Title should wrap to multiple lines; got height \(titleElement.frame.height)")
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
