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
// Kept above the `file_length` warning threshold (650) by the end-to-end
// user-flow tests (Complete/Skip/Delete/Undo/Settings/Background/Composition).
// swiftlint:disable file_length

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
    func testPriorityMarkerRendersForMidRangeValue() {
        let seed = #"{"reminders":[{"title":"Urgent item","priority":3}]}"#
        let app = launchApp(seedJSON: seed)

        // The marker Text renders "!!!" but carries the accessibility label
        // "High priority" (level.displayName + " priority"), so UI tests match
        // the marker element by that label.
        XCTAssertTrue(
            app.staticTexts["High priority"].waitForExistence(timeout: 5),
            "Priority-3 reminder should render the high-priority marker")
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
        app.staticTexts["Privacy Policy"].tap()
        XCTAssertTrue(
            app.navigationBars["Privacy Policy"].waitForExistence(timeout: 2),
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

    // MARK: - Pin wallpaper toggle

    @MainActor
    func testPinWallpaperTogglePersistsAcrossRelaunch() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.staticTexts["Background"].waitForExistence(timeout: 3))
        app.staticTexts["Background"].tap()

        let pinToggle = app.switches["Pin wallpaper"]
        XCTAssertTrue(pinToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(pinToggle.value as? String, "0", "Pin wallpaper should default to off")

        // Flip on.
        XCTAssertTrue(flipToggle(pinToggle, target: "1"))

        // Back-navigate → Done → terminate.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()

        // Relaunch with --ui-testing to avoid resetPersistedState() wipe.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.staticTexts["Background"].tap()
        let persistedToggle = relaunched.switches["Pin wallpaper"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            persistedToggle.value as? String, "1",
            "Pin wallpaper on should persist across relaunch")

        // Flip back off and verify it persists as off (not a one-way latch).
        XCTAssertTrue(flipToggle(persistedToggle, target: "0"))
        relaunched.navigationBars.buttons.firstMatch.tap()
        relaunched.buttons["Done"].tap()
        relaunched.terminate()

        let thirdLaunch = XCUIApplication()
        thirdLaunch.launchArguments = ["--ui-testing"]
        thirdLaunch.launch()
        thirdLaunch.buttons["Settings"].tap()
        thirdLaunch.staticTexts["Background"].tap()
        let offToggle = thirdLaunch.switches["Pin wallpaper"]
        XCTAssertTrue(offToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(
            offToggle.value as? String, "0",
            "Pin wallpaper off should persist across relaunch")
    }

    // MARK: - Background refresh

    @MainActor
    func testBackgroundRefreshButtonExists() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.staticTexts["Background"].waitForExistence(timeout: 3), "Settings should show Background")
        app.staticTexts["Background"].tap()

        let refreshButton = app.buttons["Refresh wallpaper"]
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

    // MARK: - Completion glow

    /// Uses `--ui-testing` (not `--seed`) for both launches: seeding calls
    /// `resetPersistedState()` and would wipe the key under test.
    @MainActor
    func testCompletionGlowTogglePersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-glow-preference"]
        app.launch()
        app.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3))
        app.staticTexts["Reminder"].tap()
        let toggle = app.switches["Completion glow"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "Completion glow should default to on")
        XCTAssertTrue(flipToggle(toggle, target: "0"), "Tapping should disable the glow")

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        relaunched.buttons["Settings"].tap()
        relaunched.staticTexts["Reminder"].tap()
        let persistedToggle = relaunched.switches["Completion glow"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(persistedToggle.value as? String, "0", "Completion-glow-off should persist across relaunch")
    }

    @MainActor
    func testCompletionGlowDoesNotAppearWhenDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", #"{"reminders":[{"title":"Buy groceries"}]}"#, "--ui-testing-glow"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Disable the glow, then complete the only reminder.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Reminder"].waitForExistence(timeout: 3))
        app.staticTexts["Reminder"].tap()
        let toggle = app.switches["Completion glow"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertTrue(flipToggle(toggle, target: "0"), "Tapping should disable the glow")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        app.staticTexts["Buy groceries"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        XCTAssertTrue(app.staticTexts["No Reminders"].waitForExistence(timeout: 5), "Completing should empty the list")
        // The overlay must never appear once the preference is off.
        XCTAssertFalse(app.otherElements["completionGlowOverlay"].exists, "Glow should be suppressed when disabled")
    }

    @MainActor
    func testCompletionGlowFlashesWhenEnabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--seed", #"{"reminders":[{"title":"Buy groceries"}]}"#, "--ui-testing-glow"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        app.staticTexts["Buy groceries"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // Glow duration is extended to 2 s under the seam, so `waitForExistence`
        // is deterministic.
        XCTAssertTrue(
            app.otherElements["completionGlowOverlay"].waitForExistence(timeout: 3),
            "Glow overlay should flash briefly after completion")
    }

    // MARK: - Swipe prompt

    /// The prompt text is accessibility-hidden (design requirement) so the only
    /// observable element is the Dismiss button. `--reset-swipe-preference`
    /// clears the persistent key so the prompt deterministically defaults ON.
    @MainActor
    func testSwipePromptAppearsUnderUITesting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-swipe-preference"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["Dismiss swipe prompt"].waitForExistence(timeout: 3),
            "Swipe prompt should be visible under --ui-testing")
    }

    /// Uses `--ui-testing` (not `--seed`) for both launches: seeding calls
    /// `resetPersistedState()` and would wipe the key under test.
    @MainActor
    func testDismissSwipePromptHidesItAndPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-swipe-preference"]
        app.launch()
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
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["--ui-testing"]
        relaunched.launch()
        XCTAssertTrue(relaunched.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        XCTAssertFalse(
            relaunched.buttons["Dismiss swipe prompt"].exists,
            "Prompt should stay gone across relaunch after Dismiss")
    }

    /// The Settings toggle flips the same persisted key; verify the round-trip
    /// off → on through the Interface Settings screen.
    @MainActor
    func testSwipePromptToggleRoundTripsViaSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-swipe-preference"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Open Settings → Interface.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3))
        app.staticTexts["Interface"].tap()

        // Toggle should be ON by default.
        let toggle = app.switches["Show swipe prompt"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "1", "Show swipe prompt should default to on")

        // Flip it off.
        XCTAssertTrue(flipToggle(toggle), "Tapping should disable the prompt")

        // Back to root, Done.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Prompt should no longer appear on the main screen.
        XCTAssertFalse(
            app.buttons["Dismiss swipe prompt"].exists,
            "Prompt should be hidden after toggling off in Settings")

        // Re-open Settings → Interface, verify toggle value persists.
        app.buttons["Settings"].tap()
        app.staticTexts["Interface"].tap()
        let toggleAfterReopen = app.switches["Show swipe prompt"]
        XCTAssertTrue(toggleAfterReopen.waitForExistence(timeout: 3))
        XCTAssertEqual(
            toggleAfterReopen.value as? String, "0",
            "Show swipe prompt should still be off after closing Settings")

        // Flip it back on.
        XCTAssertTrue(flipToggle(toggleAfterReopen, target: "1"), "Tapping should re-enable the prompt")
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Prompt should be visible again.
        XCTAssertTrue(
            app.buttons["Dismiss swipe prompt"].waitForExistence(timeout: 3),
            "Prompt should reappear after re-enabling in Settings")
    }

    // MARK: - Undo

    @MainActor
    func testUndoButtonAppearsAfterCompleteAndUndoRemovesReminder() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the reminder via action button.
        let completeButton = app.buttons["Complete reminder"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()

        // Undo button should appear after completion.
        let undoButton = app.buttons["Undo completion"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3), "Undo button should appear after completing a reminder")

        // Tap undo.
        undoButton.tap()

        // Reminder should reappear.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 3),
            "Reminder should reappear after undo")

        // Undo button should disappear.
        XCTAssertFalse(undoButton.exists, "Undo button should disappear after undoing")
    }

    @MainActor
    func testUndoButtonHiddenWhenToggleOff() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Complete the reminder to make undo button appear.
        let completeButton = app.buttons["Complete reminder"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 3))
        completeButton.tap()

        let undoButton = app.buttons["Undo completion"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 3))

        // Open settings, navigate to Interface, flip showUndoButton off.
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3))
        app.staticTexts["Interface"].tap()

        let showUndoToggle = app.switches["Show undo button"]
        XCTAssertTrue(showUndoToggle.waitForExistence(timeout: 3))
        let flipped = flipToggle(showUndoToggle, target: "0")
        XCTAssertTrue(flipped, "Show undo button toggle should be off")

        // The Done button lives on the settings root, so pop back to it first.
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Done"].tap()

        // Undo button should be gone.
        XCTAssertFalse(undoButton.exists, "Undo button should be hidden when toggle is off")
    }

    @MainActor
    func testUndoButtonDoesNotAppearWithoutCompletion() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Undo button should not exist on fresh launch.
        XCTAssertFalse(app.buttons["Undo completion"].exists, "Undo button should not appear without a completion")
    }

    // MARK: - Freemium gate

    @MainActor
    func testUpgradePromptAppearsWhenGated() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":false}"#
        let app = launchApp(seedJSON: seed)

        // The upgrade prompt should appear instead of action buttons.
        let upgradeButton = app.buttons["Upgrade to unlock unlimited completions"]
        XCTAssertTrue(
            upgradeButton.waitForExistence(timeout: 5),
            "Upgrade prompt should appear when gated")

        // It must be a wide pill, not the small circular control plate — the
        // label text needs room to breathe.
        let buttonFrame = upgradeButton.frame
        XCTAssertGreaterThan(
            buttonFrame.width, 200,
            "Upgrade button should be much wider than a small circular plate")
        XCTAssertGreaterThan(
            buttonFrame.width, buttonFrame.height,
            "Upgrade button should be wider than it is tall (pill, not circle)")
    }

    @MainActor
    func testActionClusterAppearsWhenEntitledAtCap() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":true}"#
        let app = launchApp(seedJSON: seed)

        // Action buttons should appear because the user is entitled.
        let completeButton = app.buttons["Complete reminder"]
        XCTAssertTrue(
            completeButton.waitForExistence(timeout: 5),
            "Complete button should appear when entitled even at cap")
    }

    @MainActor
    func testSettingsHasPurchaseRow() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#
        let app = launchApp(seedJSON: seed)

        // Open settings.
        app.buttons["Settings"].tap()

        // The Purchase/Unlock row should be visible.
        let unlockRow = app.buttons["Unlock"]
        XCTAssertTrue(
            unlockRow.waitForExistence(timeout: 3),
            "Settings should have an Unlock row")
    }

    @MainActor
    func testPurchaseSheetHasRestoreButton() {
        let seed = #"{"reminders":[{"title":"Buy groceries"}],"completionCount":100,"isEntitled":false}"#
        let app = launchApp(seedJSON: seed)

        // Tap the upgrade prompt.
        app.buttons["Upgrade to unlock unlimited completions"].tap()

        // The purchase sheet has a Restore Purchases button.
        let restoreButton = app.buttons["Restore Purchases"]
        XCTAssertTrue(
            restoreButton.waitForExistence(timeout: 3),
            "Purchase sheet should have a Restore Purchases button")
    }
}
