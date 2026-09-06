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

import XCTest

final class SkipNudgeUITests: SingleThreadUITestCase {

    /// Seeding the count at 5 makes the very first Skip tap the 6th, so the
    /// nudge interrupt fires with one interaction.
    private static let seed = #"{"reminders":[{"title":"Buy groceries"}],"skipCounts":{"Buy groceries":5}}"#

    // MARK: - iPad layout

    /// On iPad the nudged card must hug its content instead of stretching the
    /// borderedProminent banner edge-to-edge across the padded row. Red on
    /// `origin/main` (banner fills ~rowWidth − 80); green once the card is
    /// width-capped.
    @MainActor
    func testNudgedCardDoesNotSpanRowOnIPad() {
        let app = launchSeeded(Self.seed)

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.staticTexts["Buy groceries"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        let banner = app.buttons["skipNudgeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 3))

        let rowWidth = app.windows.firstMatch.frame.width
        // Strictly less-than is deliberate: before the fix the banner equals
        // the padded row width on iPad, so `<=` would falsely pass.
        XCTAssertLessThan(
            banner.frame.width,
            rowWidth - 80,
            "Nudged card should hug its content, not span the full row width")
    }
}
