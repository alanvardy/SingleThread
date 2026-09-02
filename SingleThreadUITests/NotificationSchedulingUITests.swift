#if os(iOS)
import XCTest

final class NotificationSchedulingUITests: SingleThreadUITestCase {

    /// Enables the notifications toggle via Settings → Notifications, accepting
    /// the system authorization prompt if it appears, then returns to the main
    /// screen. Uses the `flipToggle` pattern so the inner switch control is
    /// tapped (a direct tap on the Form row is swallowed by SwiftUI).
    @MainActor
    private func enableNotifications(_ app: XCUIApplication) {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsNotificationsRow"].waitForExistence(timeout: 3))
        app.buttons["settingsNotificationsRow"].tap()

        let toggle = app.switches["notificationsEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        XCTAssertTrue(flipToggle(toggle, target: "1"), "Notifications should flip ON")
        usleep(500_000)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["settingsDoneButton"].tap()
    }

    @MainActor
    private func backgroundAndForeground(_ app: XCUIApplication) async throws {
        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        app.activate()
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    @MainActor
    func testSchedulingOnBackground() async throws {
        let app = launchSeeded(
            #"{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}"#,
            extra: ["--ui-testing-notifications"])

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        enableNotifications(app)

        try await backgroundAndForeground(app)

        let lastSchedule = statusLabel(app, identifier: "lastScheduleStatus")
        XCTAssertNotNil(lastSchedule, "A notification should have been scheduled on background")
        XCTAssertTrue(
            lastSchedule?.contains("count=1") == true,
            "Exactly one notification scheduled, got: \(lastSchedule ?? "nil")")
        XCTAssertTrue(lastSchedule?.contains("id=app.alanvardy.SingleThread.idle-reminder") == true)
        XCTAssertTrue(lastSchedule?.contains("body=You have 2 reminders waiting — open SingleThread!") == true)
        // 48h default interval.
        XCTAssertTrue(
            lastSchedule?.contains("interval=172800") == true,
            "48h default interval, got: \(lastSchedule ?? "nil")")
    }

    @MainActor
    func testCancelOnForeground() async throws {
        let app = launchSeeded(
            #"{"reminders":[{"title":"Buy groceries"}]}"#,
            extra: ["--ui-testing-notifications"])

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        enableNotifications(app)

        try await backgroundAndForeground(app)

        // Foregrounding (`app.activate()`) should have cancelled pending requests,
        // so the pending seam reports zero.
        let pending = statusLabel(app, identifier: "pendingStatus")
        XCTAssertNotNil(pending, "Pending seam should be present")
        XCTAssertTrue(
            pending?.contains("count=0") == true,
            "Pending should be cancelled on foreground, got: \(pending ?? "nil")")

        // The request WAS scheduled before cancellation.
        let lastSchedule = statusLabel(app, identifier: "lastScheduleStatus")
        XCTAssertTrue(
            lastSchedule?.contains("count=1") == true,
            "A request should have been scheduled before cancellation")
    }

    @MainActor
    func testNoScheduleWhenDisabled() async throws {
        let app = launchSeeded(
            #"{"reminders":[{"title":"Buy groceries"}]}"#,
            extra: ["--ui-testing-notifications"])

        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        // Leave the toggle OFF (default).

        try await backgroundAndForeground(app)

        // Nothing scheduled, so the last-schedule status is never set.
        let lastSchedule = statusLabel(app, identifier: "lastScheduleStatus")
        XCTAssertFalse(
            lastSchedule?.contains("count=1") == true,
            "No notification should be scheduled when the toggle is off")

        let pending = statusLabel(app, identifier: "pendingStatus")
        XCTAssertTrue(
            pending?.contains("count=0") == true,
            "No pending notification when disabled, got: \(pending ?? "nil")")
    }

    @MainActor
    func testNoScheduleWhenNoReminders() async throws {
        let app = launchSeeded(
            #"{"reminders":[]}"#,
            extra: ["--ui-testing-notifications"])

        XCTAssertTrue(app.staticTexts["emptyStateTitle"].waitForExistence(timeout: 5))
        enableNotifications(app)

        try await backgroundAndForeground(app)

        // No reminders to schedule for, so the last-schedule status is never set.
        let lastSchedule = statusLabel(app, identifier: "lastScheduleStatus")
        XCTAssertFalse(
            lastSchedule?.contains("count=1") == true,
            "No notification should be scheduled when no reminders exist")

        let pending = statusLabel(app, identifier: "pendingStatus")
        XCTAssertTrue(
            pending?.contains("count=0") == true,
            "No pending notification with no reminders, got: \(pending ?? "nil")")
    }
}
#endif
