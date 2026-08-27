import XCTest

final class SingleThreadWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapRevealsConfirmationDialog() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // The --ui-testing seam seeds a mock "Buy groceries" reminder, so the
        // reminder card (with the onTapGesture target) is presented.
        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Reminder card should be displayed")
        title.tap()

        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(
            refresh.waitForExistence(timeout: 5),
            "Tapping the card should present the Refresh confirmation dialog")
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Reminder card should be displayed")

        #if os(watchOS)
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])
        #endif
    }

    @MainActor
    func testGuideAppearsOnFirstLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-guide"]
        app.launch()

        // Guide overlay should be visible
        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 5), "Guide overlay should show 'Got it' button on first launch")

        // Card should NOT be tappable through the overlay: tapping the title must
        // not present the confirmation dialog (isHittable is unreliable on watchOS,
        // so assert the blocking behavior directly via a coordinate tap —
        // `element.tap()` throws when an intentionally blocked element isn't
        // hittable).
        let title = app.staticTexts["Buy groceries"]
        title.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(
            app.buttons["Refresh"].waitForExistence(timeout: 2),
            "Reminder card should be blocked by the guide overlay")

        // Dismiss
        gotIt.tap()

        // After dismiss, the card should be visible and interactive
        XCTAssertTrue(title.waitForExistence(timeout: 3), "Reminder card should appear after dismissing guide")
        title.tap()
        XCTAssertTrue(
            app.buttons["Refresh"].waitForExistence(timeout: 3),
            "Card should be tappable after dismissing the guide")
    }

    @MainActor
    func testGuideDoesNotReappearOnSubsequentLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Without --reset-guide, the guide should not appear
        let gotIt = app.buttons["Got it"]
        XCTAssertFalse(gotIt.waitForExistence(timeout: 3), "Guide should not appear on subsequent launches")

        // Card should be directly visible
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAccessibilityAuditWithGuide() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-guide"]
        app.launch()

        let gotIt = app.buttons["Got it"]
        XCTAssertTrue(gotIt.waitForExistence(timeout: 5))

        #if os(watchOS)
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])
        #endif
    }
}
