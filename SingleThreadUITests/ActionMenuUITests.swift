//  ActionMenuUITests.swift
//
//  End-to-end action-menu flows: with the action-buttons toggle ON (the `--seed`
//  seam turns it on, see `AppViewModel.seededStore`), the bottom-bar Skip opens
//  a three-action menu (Skip / Reschedule / Delete) instead of skipping
//  directly. With the toggle OFF the Skip swipe acts directly (the toggle-off
//  path is behaviorally identical to the pre-menu app).

import SingleThreadCore
import XCTest

final class ActionMenuUITests: SingleThreadUITestCase {

    private static let seed = #"{"reminders":[{"title":"Buy groceries"}]}"#

    // MARK: - Skip (direct action in the menu)

    /// Toggle ON: tapping Skip presents the menu; choosing Skip advances the
    /// card (mirrors `ActionButtonsUITests`' skip-advances flow through the
    /// dialog).
    @MainActor
    func testActionMenuSkipAdvancesWhenToggleOn() {
        let app = launchSeeded(Self.seed)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        app.buttons["skipButton"].tap()
        let dialogSkip = app.buttons["Skip"]
        XCTAssertTrue(
            dialogSkip.waitForExistence(timeout: 3),
            "Toggle ON: tapping Skip should present the action menu, not skip directly")
        dialogSkip.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "The menu's Skip should advance to the All Done state")
    }

    // MARK: - Delete (destructive action in the menu)

    /// Toggle ON: the menu's Delete removes the reminder.
    @MainActor
    func testActionMenuDeleteRemovesWhenToggleOn() {
        let app = launchSeeded(Self.seed)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        app.buttons["skipButton"].tap()
        // iOS confirmation-dialog buttons can be exposed twice in the a11y tree
        // (popover parent + child) when they carry an identifier, so match the
        // first node.
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(
            delete.waitForExistence(timeout: 3),
            "The action menu should offer Delete")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Deleting the only reminder should empty the list")
    }

    // MARK: - Reschedule (sheet flow)

    /// Toggle ON: the menu's Reschedule opens the shared `RescheduleSheet`;
    /// confirming writes a due date onto the card.
    @MainActor
    func testActionMenuRescheduleShowsSheetWhenToggleOn() {
        let app = launchSeeded(Self.seed)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        app.buttons["skipButton"].tap()
        // iOS confirmation-dialog buttons can be exposed twice in the a11y tree
        // (popover parent + child) when they carry an identifier, so match the
        // first node.
        let reschedule = app.buttons["Reschedule"].firstMatch
        XCTAssertTrue(
            reschedule.waitForExistence(timeout: 3),
            "The action menu should offer Reschedule")
        reschedule.tap()

        let confirm = app.buttons["rescheduleConfirmButton"]
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 3),
            "Reschedule should open the reschedule sheet")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["dueDateText"].waitForExistence(timeout: 5),
            "Rescheduling should stamp a due date on the card")
    }

    // MARK: - Toggle OFF

    /// Toggle OFF (flipped in Settings): the bottom-bar cluster is replaced by
    /// the plain mic (no `skipButton`), and the Skip swipe acts directly —
    /// no action menu.
    @MainActor
    func testSkipActsDirectlyWhenToggleOff() {
        let app = launchSeeded(Self.seed)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Flip the action-buttons toggle OFF in Settings → Interface.
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsInterfaceRow"].waitForExistence(timeout: 3))
        app.buttons["settingsInterfaceRow"].tap()
        let toggle = app.switches["showActionButtonsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertTrue(flipToggle(toggle, target: "0"), "Action-buttons toggle should flip OFF")
        usleep(300_000)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsDoneButton"].tap()

        // Toggle OFF: the cluster (and its Skip button) must not render.
        XCTAssertFalse(
            app.buttons["skipButton"].exists,
            "Toggle OFF: the action cluster should be replaced by the plain mic")

        // The Skip swipe is the toggle-off skip path: direct, no action menu.
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Swipe reveal should show the Skip action")
        skip.tap()
        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Toggle OFF: Skip should act directly without the action menu")
    }
}
