import XCTest

final class SingleThreadWatchUITests: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndRenderSmoke() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Reminder card should render")
        XCTAssertTrue(
            app.staticTexts["Don't forget the milk"].exists,
            "Reminder notes should render")
        XCTAssertTrue(
            app.staticTexts["priorityMarker"].exists,
            "Priority marker \"!!\" should render")

        try app.performAccessibilityAudit(
            for: [.sufficientElementDescription, .trait])
    }

    // MARK: Private

    /// Relocated verbatim from SingleThreadWatchUITestsFlows.swift:298-304
    /// (deleted in Stage 2).
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }
}
