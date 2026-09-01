import XCTest

final class ActionButtonsUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it.
    // Run once (not once per target app configuration): both methods render the
    // same `--ui-testing` UI; the per-config multiplier only adds redundant cold
    // launches on CI. The audit categories/CI-carve-out are otherwise untouched.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testActionButtonsRenderAndSkipAdvancesCard() {
        // `--ui-testing` seeds a single reminder AND turns the action-buttons
        // toggle on (see `SingleThreadApp.makeStore`), so the Complete/Skip
        // cluster presents deterministically without EventKit access.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let complete = app.buttons["completeButton"]
        XCTAssertTrue(
            complete.waitForExistence(timeout: 5),
            "Complete button should be present beside the mic")
        let skip = app.buttons["skipButton"]
        XCTAssertTrue(
            skip.waitForExistence(timeout: 5),
            "Skip button should be present beside the mic")

        // Tap Skip; the settle-delayed skip write advances the visible reminder,
        // which lands on the allSkipped "All Done" branch (bottom bar disappears).
        skip.tap()
        XCTAssertTrue(
            app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5),
            "Skipping should advance the displayed card to the All Done state")
    }

    @MainActor
    func testActionButtonsAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let complete = app.buttons["completeButton"]
        XCTAssertTrue(
            complete.waitForExistence(timeout: 5),
            "Complete button should exist before auditing")
        let skip = app.buttons["skipButton"]
        XCTAssertTrue(
            skip.waitForExistence(timeout: 5),
            "Skip button should exist before auditing")

        // Audit the two new buttons' accessibility: dynamic type, hit regions,
        // element descriptions, and traits. macOS offers a different audit set.
        #if os(iOS)
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
            )
        #else
            try app.performAccessibilityAudit()
        #endif
    }
}
