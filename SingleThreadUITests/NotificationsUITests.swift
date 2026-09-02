#if os(iOS)
import XCTest

final class NotificationsUITests: SingleThreadUITestCase {

    /// The menu-style picker button's label combines the title and the current
    /// value (e.g. "Remind after, 48 hours"). The picker has the
    /// `notificationIntervalPicker` accessibility identifier.
    @MainActor
    private func remindAfterPicker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["notificationIntervalPicker"].firstMatch
    }

    /// Navigates Settings → Notifications, asserts the defaults (toggle OFF,
    /// interval 48h), enables the toggle (accepting the authorization prompt if it
    /// appears), switches the interval to 24 hours, and returns to the main screen.
    @MainActor
    private func configureNotifications(_ app: XCUIApplication) {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsNotificationsRow"].waitForExistence(timeout: 3))
        app.buttons["settingsNotificationsRow"].tap()

        let toggle = app.switches["notificationsEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertEqual(toggle.value as? String, "0", "Notifications should default to off")
        let picker = remindAfterPicker(app)
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertTrue(picker.label.contains("48 hours"), "Interval should default to 48 hours, got: \(picker.label)")

        XCTAssertTrue(flipToggle(toggle, target: "1"), "Notifications should flip ON")
        usleep(500_000)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        picker.tap()
        XCTAssertTrue(app.buttons["24 hours"].waitForExistence(timeout: 2))
        app.buttons["24 hours"].tap()

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsDoneButton"].tap()
    }

    @MainActor
    func testFullNotificationFlow() async throws {
        let app = launchSeeded(
            #"{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}"#,
            extra: ["--ui-testing-notifications"])

        // 1. Verify reminders are visible.
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        configureNotifications(app)

        // 7. Background to schedule, then foreground so the seam is readable.
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        app.activate()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // 8. The scheduled request reflects the 24h picker choice persisted into
        //    the trigger (86400 s), not the 48h default (172800 s).
        let lastSchedule = statusLabel(app, identifier: "lastScheduleStatus")
        XCTAssertNotNil(lastSchedule, "A notification should have been scheduled on background")
        XCTAssertTrue(
            lastSchedule?.contains("count=1") == true,
            "Exactly one notification scheduled, got: \(lastSchedule ?? "nil")")
        XCTAssertTrue(
            lastSchedule?.contains("id=app.alanvardy.SingleThread.idle-reminder") == true,
            "Stable identifier missing, got: \(lastSchedule ?? "nil")")
        XCTAssertTrue(
            lastSchedule?.contains("body=You have 2 reminders waiting — open SingleThread!") == true,
            "Body count mismatch, got: \(lastSchedule ?? "nil")")
        XCTAssertTrue(
            lastSchedule?.contains("interval=86400") == true,
            "24h interval expected after picker change, got: \(lastSchedule ?? "nil")")

        // 9. Foregrounding cancelled the pending requests.
        let pending = statusLabel(app, identifier: "pendingStatus")
        XCTAssertNotNil(pending, "Pending seam should be present")
        XCTAssertTrue(
            pending?.contains("count=0") == true,
            "Pending should be cancelled on foreground, got: \(pending ?? "nil")")

        // 10. Re-open Settings → Notifications to verify persistence.
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsNotificationsRow"].waitForExistence(timeout: 3))
        app.buttons["settingsNotificationsRow"].tap()

        let persistedToggle = app.switches["notificationsEnabledToggle"]
        XCTAssertTrue(persistedToggle.waitForExistence(timeout: 3))
        XCTAssertEqual(persistedToggle.value as? String, "1", "Toggle should still be ON")

        let persistedPicker = remindAfterPicker(app)
        XCTAssertTrue(persistedPicker.waitForExistence(timeout: 3))
        XCTAssertTrue(
            persistedPicker.label.contains("24 hours"),
            "Picker should still show 24 hours, got: \(persistedPicker.label)")
    }

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
