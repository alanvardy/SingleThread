#if os(iOS)
import XCTest

final class NotificationsUITests: SingleThreadUITestCase {

    @MainActor
    func testAccessibilityAudit() throws {
        let app = launchSeeded(#"{"reminders":[{"title":"Test"}]}"#)
        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))

        app.buttons["settingsButton"].tap()
        app.buttons["settingsNotificationsRow"].tap()

        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }
}
#endif
