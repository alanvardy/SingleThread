//
//  SingleThreadUITests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it. Run once (not once per target app configuration): the smoke
    // launches one deterministic app state; multiplying it by the configuration
    // count adds redundant cold launches on CI for no coverage.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndRenderSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Plain --ui-testing seeds one reminder ("Buy groceries" /
        // "Don't forget the milk", priority 5 → "!!") with
        // enableActionButtons ON, so the card + Complete/Skip/mic cluster render.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Reminder title should render")
        XCTAssertTrue(app.staticTexts["Don't forget the milk"].exists,
                      "Reminder notes should render")
        XCTAssertTrue(app.staticTexts["priorityMarker"].exists,
                      "Priority marker \"!!\" should render")
        // The action cluster is a separate async region below the card; on a
        // cold first launch (fresh simulator) it can lag the card by a beat, so
        // wait for it like the title does (mirrors the pre-collapse Flows
        // pattern, `complete.waitForExistence(timeout: 3)`).
        XCTAssertTrue(
            app.buttons["completeButton"].waitForExistence(timeout: 5),
            "Complete action should render")
        XCTAssertTrue(app.buttons["skipButton"].exists,
                      "Skip action should render")
        XCTAssertTrue(app.buttons["dictateButton"].exists,
                      "Dictate action should render")

        // Fold the CI-parity a11y audit into the smoke check, using the cheap,
        // non-rendering categories only. .dynamicType/.hitRegion can hang on
        // GitHub's virtualized runners and are covered by unit suites
        // (TextSizeTests etc.), so they are deliberately excluded — matching the
        // former CI carve-out, now applied everywhere (local and CI alike).
        try app.performAccessibilityAudit(
            for: [.sufficientElementDescription, .trait]
        )
    }
}
