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

        // watchOS confirmation-dialog actions expose their label, not the
        // SwiftUI accessibility identifier (see Flows delete test), so match by
        // the dialog button's "Refresh" label here.
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
}
