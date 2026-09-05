//
//  SkipNudgeUITests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-09-04.
//
//  End-to-end skip-nudge flows: after a reminder is skipped for the 6th time
//  (seeded via `--seed ... "skipCounts":{"<title>":5}` so one skip tap crosses
//  the threshold), the card stays put and shows the in-card nudge banner.
//  Tapping it opens a sheet with Delete / Reschedule / View-in-Reminders.

import SingleThreadCore
import XCTest

final class SkipNudgeUITests: SingleThreadUITestCase {

    /// Seeding the count at 5 makes the very first Skip tap the 6th, so the
    /// nudge interrupt fires with one interaction.
    private static let seed = #"{"reminders":[{"title":"Buy groceries"}],"skipCounts":{"Buy groceries":5}}"#

    // MARK: - Banner + Delete

    /// 6th skip keeps the card visible with the banner; tapping the banner
    /// opens the sheet; Delete empties the list.
    @MainActor
    func testSkipNudgeBannerAppearsAfterSixthSkipAndDeletes() {
        let app = launchSeeded(Self.seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

        // Skip once — crosses from 5 to 6, interrupting the cycle.
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3), "Skipping should reveal the Skip swipe action")
        skip.tap()

        // The card must stay visible with the nudge banner (not advance).
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "6th skip should keep the reminder visible")
        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "Nudge banner should appear after the 6th skip")

        // Open the nudge sheet and delete.
        banner.tap()
        XCTAssertTrue(
            app.staticTexts["nudgeSheetTitle"].waitForExistence(timeout: 3),
            "Tapping the banner should open the nudge sheet")
        let delete = app.buttons["nudgeDeleteButton"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Nudge sheet should offer Delete")
        delete.tap()

        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Deleting the nudged reminder should empty the list")
    }

    // MARK: - Reschedule

    /// The nudge sheet's Reschedule writes a new due date onto the card; the
    /// banner clears and the reminder stays visible with the new date.
    @MainActor
    func testSkipNudgeRescheduleActs() {
        let app = launchSeeded(Self.seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "Nudge banner should appear after the 6th skip")
        banner.tap()
        XCTAssertTrue(
            app.staticTexts["nudgeSheetTitle"].waitForExistence(timeout: 3),
            "Tapping the banner should open the nudge sheet")

        let reschedule = app.buttons["rescheduleConfirmButton"]
        XCTAssertTrue(reschedule.waitForExistence(timeout: 3), "Nudge sheet should offer Reschedule")
        reschedule.tap()

        // Sheet closes on success; the card shows the rescheduled due date.
        XCTAssertTrue(
            app.staticTexts["dueDateText"].waitForExistence(timeout: 5),
            "Rescheduling should stamp a due date on the card")
        XCTAssertFalse(
            app.buttons["skipNudgeBanner"].exists,
            "Rescheduling should clear the nudge banner")
    }

    // MARK: - View in Reminders

    /// The nudge sheet's View in Reminders deep-links to the reminder. Under
    /// the `--url-opener-spy` seam the app renders the opened URL as an
    /// accessible element, so we assert the deep link actually fired (prefix
    /// + UUID), not just that the button exists.
    @MainActor
    func testSkipNudgeViewInRemindersOpensURL() {
        let app = launchSeeded(Self.seed, extra: ["--url-opener-spy"])

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3), "Nudge banner should appear after the 6th skip")
        banner.tap()
        XCTAssertTrue(
            app.staticTexts["nudgeSheetTitle"].waitForExistence(timeout: 3),
            "Tapping the banner should open the nudge sheet")

        let viewInReminders = app.buttons["nudgeViewInRemindersButton"]
        XCTAssertTrue(
            viewInReminders.waitForExistence(timeout: 3),
            "Nudge sheet should offer View in Reminders")
        viewInReminders.tap()

        // The spy element renders as an `accessibilityElement(children: .ignore)`
        // (not a staticText), so `statusLabel` reads it via `otherElements` first.
        let label = statusLabel(app, identifier: "lastOpenedURL")
        XCTAssertNotNil(label, "The spy URL element should render after opening the deep link")
        let spyLabel: String = label ?? ""
        let hasPrefix = spyLabel.hasPrefix("spyURL-x-apple-reminderkit://REMCDReminder/")
        XCTAssertTrue(
            hasPrefix,
            "Expected ReminderKit deep link prefix, got: \(spyLabel)")

        // Only parse the trailing UUID when the prefix matched, so a failed
        // prefix surfaces as the friendly XCTest message above rather than a
        // dropFirst() bounds error (XCTest assertions do not abort the test).
        if hasPrefix {
            let fullURL = String(spyLabel.dropFirst("spyURL-".count))
            let uuidPortion = String(fullURL.dropFirst("x-apple-reminderkit://REMCDReminder/".count))
            XCTAssertEqual(
                uuidPortion.count, 36,
                "Expected a 36-char UUID in the deep link, got \(uuidPortion)")
        }
    }
}
