import XCTest

final class ActionButtonsUITests: XCTestCase {

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

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(
            complete.waitForExistence(timeout: 5),
            "Complete button should be present beside the mic")
        let skip = app.buttons["Skip reminder"]
        XCTAssertTrue(
            skip.waitForExistence(timeout: 5),
            "Skip button should be present beside the mic")

        // Tap Skip; the settle-delayed skip write advances the visible reminder,
        // which lands on the allSkipped "All Done" branch (bottom bar disappears).
        skip.tap()
        XCTAssertTrue(
            app.staticTexts["All Done"].waitForExistence(timeout: 5),
            "Skipping should advance the displayed card to the All Done state")
    }

    @MainActor
    func testActionButtonsAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(
            complete.waitForExistence(timeout: 5),
            "Complete button should exist before auditing")
        let skip = app.buttons["Skip reminder"]
        XCTAssertTrue(
            skip.waitForExistence(timeout: 5),
            "Skip button should exist before auditing")

        // Audit the two new buttons' accessibility: dynamic type, hit regions,
        // element descriptions, and traits.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
        )
    }
}
