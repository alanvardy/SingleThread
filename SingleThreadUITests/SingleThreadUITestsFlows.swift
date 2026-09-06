//
//  SingleThreadUITestsFlows.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-20.
//
//  User-use-case UI tests driven by the `--seed '<json>'` launch-arg seam,
//  which backs the app with an in-memory EventKit store so complete/delete/skip
//  mutate deterministically without touching a real EKEventStore.

import SingleThreadCore
import XCTest

final class SingleThreadUITestsFlows: SingleThreadUITestCase {

    // MARK: - List rendering

    @MainActor
    func testListShowsSeededReminder() {
        let app = launchSeeded(#"{"reminders":[{"title":"Buy groceries","notes":"milk"}]}"#)

        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Seeded reminder title should be displayed")
        XCTAssertTrue(
            app.staticTexts["milk"].waitForExistence(timeout: 2),
            "Seeded reminder notes should be displayed on the card")
    }

    @MainActor
    func testEmptyListShowsNoRemindersState() {
        let app = launchSeeded(#"{"reminders":[]}"#)

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Empty seeded store should render the No Reminders empty state")
    }

    @MainActor
    func testNothingDueShowsWhenRemindersHidden() {
        let app = launchSeeded(#"{"reminders":[],"hasHidden":true}"#)

        XCTAssertTrue(
            app.staticTexts["Nothing due"].waitForExistence(timeout: 5),
            "With hasHidden seeded true and no reminders, 'Nothing due' should appear")
    }

    // MARK: - Skip refetch

    /// The `--seed` schema has no `completed` flag, so the cross-device
    /// completion is simulated the only way a single app process can: the
    /// Complete swipe action (runs the real iOS save → settle → reload round
    /// trip). After completing "CrossDevice" the app shows the next reminder
    /// ("ToSkip"); skipping it fires the Stage 4 background refetch that must
    /// not resurrect the completed card.
    @MainActor
    func testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder() {
        // Three reminders: "CrossDevice" is completed (simulating the other
        // device), "ToSkip" is skipped (triggering the new background refetch),
        // "Remaining" is the only one left visible. Priorities must fall in
        // distinct rank buckets (1–4 high, 5 medium, 6–9 low) or the sort's
        // title tie-break can reorder them.
        // swiftlint:disable:next line_length
        let seed = #"{"reminders":[{"title":"CrossDevice","priority":1},{"title":"ToSkip","priority":5},{"title":"Remaining","priority":9}]}"#
        let app = launchSeeded(seed)

        // 1. Complete "CrossDevice" (simulates a cross-device completion).
        XCTAssertTrue(app.staticTexts["CrossDevice"].waitForExistence(timeout: 5))
        app.staticTexts["CrossDevice"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // 2. Skip "ToSkip" (fires the Stage 4 background refetch).
        XCTAssertTrue(app.staticTexts["ToSkip"].waitForExistence(timeout: 5))
        app.staticTexts["ToSkip"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        // 3. Only the non-completed, non-skipped reminder is visible.
        XCTAssertTrue(
            app.staticTexts["Remaining"].waitForExistence(timeout: 5),
            "The remaining reminder should be the only visible card")
        XCTAssertTrue(
            app.staticTexts["CrossDevice"].waitForNonExistence(timeout: 5),
            "Completed card must not resurrect")
        XCTAssertTrue(
            app.staticTexts["ToSkip"].waitForNonExistence(timeout: 5),
            "Skipped card must stay hidden")
    }

    // MARK: - About

    @MainActor
    func testAboutModalShowsAttribution() {
        let app = launchSeeded(#"{"reminders":[]}"#)

        XCTAssertTrue(app.staticTexts.firstMatch.waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()

        // The About row sits at the bottom of the Settings List; scroll if needed.
        let about = app.buttons["settingsAboutRow"]
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

    // MARK: - Background + pin wallpaper toggles

    /// Both Background sub-view toggles persist across relaunch. One merged
    /// test covers both directions (bg-off, pin-on, pin-off) in 3 launches
    /// instead of the previous 5 (2+3): launch1 --seed flips both, launch2
    /// --ui-testing verifies both flipped values plus pin-off, launch3
    /// --ui-testing verifies the pin-off persisted (not a one-way latch).
    @MainActor
    func testBackgroundAndPinTogglesPersistAcrossRelaunch() {
        // Launch 1 (--seed): flip both toggles in the Background sub-view.
        let app = launchSeeded(#"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.buttons["settingsBackgroundRow"].waitForExistence(timeout: 3))
        app.buttons["settingsBackgroundRow"].tap()

        let bgToggle = app.switches["backgroundToggle"]
        XCTAssertTrue(bgToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(bgToggle.value as? String, "1", "Background should default to on")
        XCTAssertTrue(flipToggle(bgToggle), "Tapping should hide the background")

        let pinToggle = app.switches["pinWallpaperToggle"]
        XCTAssertTrue(pinToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(pinToggle.value as? String, "0", "Pin wallpaper should default to off")
        XCTAssertTrue(flipToggle(pinToggle, target: "1"), "Tapping should pin the wallpaper")

        // The done button lives on the settings root, so pop back to it first.
        app.navigationBars.buttons["Settings"].tap()
        app.buttons["settingsDoneButton"].tap()
        app.terminate()

        // Launch 2 (--ui-testing): both flips persisted — a `--seed` relaunch
        // would call `resetPersistedState()` and wipe the very keys under test.
        let relaunched = launchApp(arguments: ["--ui-testing"])
        relaunched.buttons["settingsButton"].tap()
        relaunched.buttons["settingsBackgroundRow"].tap()

        let persistedBg = relaunched.switches["backgroundToggle"]
        XCTAssertTrue(persistedBg.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedBg.value as? String, "0",
            "Background-off should persist across relaunch")

        let persistedPin = relaunched.switches["pinWallpaperToggle"]
        XCTAssertTrue(persistedPin.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedPin.value as? String, "1",
            "Pin wallpaper on should persist across relaunch")

        // Flip pin back off and verify it persists as off (not a one-way latch).
        XCTAssertTrue(flipToggle(persistedPin, target: "0"))
        relaunched.navigationBars.buttons["Settings"].tap()
        relaunched.buttons["settingsDoneButton"].tap()
        relaunched.terminate()

        // Launch 3 (--ui-testing): pin-off persisted.
        let thirdLaunch = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(thirdLaunch.buttons["settingsButton"].waitForExistence(timeout: 5))
        thirdLaunch.buttons["settingsButton"].tap()
        XCTAssertTrue(thirdLaunch.buttons["settingsBackgroundRow"].waitForExistence(timeout: 3))
        thirdLaunch.buttons["settingsBackgroundRow"].tap()
        let offToggle = thirdLaunch.switches["pinWallpaperToggle"]
        XCTAssertTrue(offToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            offToggle.value as? String, "0",
            "Pin wallpaper off should persist across relaunch")
    }

    // MARK: - Background refresh

    @MainActor
    func testBackgroundRefreshButtonExists() {
        let app = launchSeeded(#"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.buttons["settingsBackgroundRow"].waitForExistence(timeout: 3))
        app.buttons["settingsBackgroundRow"].tap()

        let refreshButton = app.buttons["refreshWallpaperButton"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3), "Background settings should show the refresh button")
        XCTAssertTrue(refreshButton.isHittable)

        // Tap triggers forceRefresh(); the real URLSession may hit the network.
        // We assert only that the control is present and interactive, never the
        // fetched image (headless tests cannot assert rendering or network).
        refreshButton.tap()
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 5),
            "Refresh button should remain in the tree after tap without crashing")
    }

    // MARK: - Code blocks

    @MainActor
    func testCodeBlocksRenderWithoutBacktickFences() {
        let seed = #"{"reminders":[{"title":"Use `map`","notes":"```\nlet x = 1\n```"}]}"#
        let app = launchSeeded(seed)

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

    // MARK: - Show list + completion glow toggles

    /// Both Reminder sub-view toggles persist across relaunch. One merged test
    /// covers show-list-on and glow-off in 2 launches instead of 4 (2+2):
    /// launch1 --ui-testing flips both, launch2 --ui-testing verifies both
    /// persisted. Keeps `--ui-testing` (not `--seed`) — seeding would call
    /// `resetPersistedState()` and wipe the keys under test.
    @MainActor
    func testReminderTogglesPersistAcrossRelaunch() {
        let app = launchApp(arguments: ["--ui-testing", "--reset-glow-preference"])
        app.buttons["Settings"].tap()

        // Navigate into the Reminder sub-view.
        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3))
        app.buttons["settingsReminderRow"].tap()

        let listToggle = app.switches["showListToggle"]
        XCTAssertTrue(listToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(listToggle.value as? String, "0", "Show list should default to off")
        XCTAssertTrue(flipToggle(listToggle, target: "1"), "Tapping should enable Show list")

        let glowToggle = app.switches["showCompletionGlowToggle"]
        XCTAssertTrue(glowToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(glowToggle.value as? String, "1", "Completion glow should default to on")
        XCTAssertTrue(flipToggle(glowToggle, target: "0"), "Tapping should disable the glow")

        // The done button lives on the settings root, so pop back to it first.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsDoneButton"].tap()
        app.terminate()

        let relaunched = launchApp(arguments: ["--ui-testing"])
        relaunched.buttons["settingsButton"].tap()
        relaunched.buttons["settingsReminderRow"].tap()

        let persistedList = relaunched.switches["showListToggle"]
        XCTAssertTrue(persistedList.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedList.value as? String, "1",
            "Show-list-on should persist across relaunch")

        let persistedGlow = relaunched.switches["showCompletionGlowToggle"]
        XCTAssertTrue(persistedGlow.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedGlow.value as? String, "0",
            "Completion-glow-off should persist across relaunch")
    }

    // MARK: - Swipe prompt

    /// The prompt text is accessibility-hidden (design requirement) so the only
    /// observable element is the Dismiss button. `--reset-swipe-preference`
    /// clears the persistent key so the prompt deterministically defaults ON.
    @MainActor
    func testSwipePromptAppearsUnderUITesting() {
        let app = launchApp(arguments: ["--ui-testing", "--reset-swipe-preference"])

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Dismiss swipe prompt"].waitForExistence(timeout: 3),
            "Swipe prompt should be visible under --ui-testing")
    }

    /// Uses `--ui-testing` (not `--seed`) for both launches: seeding calls
    /// `resetPersistedState()` and would wipe the key under test.
    @MainActor
    func testDismissSwipePromptHidesItAndPersistsAcrossRelaunch() {
        let app = launchApp(arguments: ["--ui-testing", "--reset-swipe-preference"])
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Dismiss the prompt.
        let dismissButton = app.buttons["Dismiss swipe prompt"]
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 3))
        dismissButton.tap()

        // Prompt should be gone.
        XCTAssertFalse(
            dismissButton.exists,
            "Prompt should be gone after Dismiss tap")

        app.terminate()

        // Relaunch with --ui-testing (NOT --seed — that would reset persisted state).
        let relaunched = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(relaunched.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            relaunched.buttons["Dismiss swipe prompt"].exists,
            "Prompt should stay gone across relaunch after Dismiss")
    }

    // MARK: - Freemium gate

    @MainActor
    func testPurchaseSheetHasRestoreButton() {
        let cap = EntitlementStore.freemiumCap
        let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":\#(cap),"isEntitled":false}"#
        let app = launchSeeded(seed)

        // Tap the upgrade prompt.
        app.buttons["upgradeButton"].tap()

        // The purchase sheet has a Restore Purchases button.
        let restoreButton = app.buttons["restorePurchasesButton"]
        XCTAssertTrue(
            restoreButton.waitForExistence(timeout: 3),
            "Purchase sheet should have a Restore Purchases button")
    }
}
