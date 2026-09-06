import XCTest

final class SingleThreadWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
}
