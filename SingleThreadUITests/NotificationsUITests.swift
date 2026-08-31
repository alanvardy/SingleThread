import XCTest

final class NotificationsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches with `--seed`. The notifications scheduling seam flag is opt-in
    /// (`notificationsSeam:`) so the accessibility-audit test runs with the seam
    /// overlay hidden, exactly as the plan specifies.
    @MainActor
    private func launchApp(seedJSON: String, notificationsSeam: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["--seed", seedJSON]
        if notificationsSeam {
            arguments.append("--ui-testing-notifications")
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// SwiftUI Form rows expose a nested switch control; tapping the outer row
    /// is swallowed, so tap the inner control until it flips to the target.
    @MainActor
    private func flipToggle(_ toggle: XCUIElement, target: String = "1") -> Bool {
        let inner = toggle.switches.firstMatch
        let tapTarget = inner.exists ? inner : toggle
        for _ in 0..<3 {
            if toggle.value as? String == target { return true }
            tapTarget.tap()
            let deadline = Date().addingTimeInterval(1)
            while Date() < deadline {
                if toggle.value as? String == target { return true }
                usleep(100_000)
            }
        }
        return toggle.value as? String == target
    }

    /// The menu-style picker button's label combines the title and the current
    /// value (e.g. "Remind after, 48 hours"), so match with a prefix predicate.
    @MainActor
    private func remindAfterPicker(_ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Remind after"))
            .firstMatch
    }

    /// Reads an app-side seam status element's label. The UI-test runner cannot
    /// query the app's own notification store, so assertions read the pending /
    /// last-schedule snapshots the app exposes under `--ui-testing-notifications`.
    @MainActor
    private func statusLabel(_ app: XCUIApplication, identifier: String) -> String? {
        let other = app.otherElements[identifier]
        if other.waitForExistence(timeout: 3) {
            return other.label
        }
        let text = app.staticTexts[identifier]
        if text.waitForExistence(timeout: 1) {
            return text.label
        }
        return nil
    }

    /// Navigates Settings → Notifications, asserts the defaults (toggle OFF,
    /// interval 48h), enables the toggle (accepting the authorization prompt if it
    /// appears), switches the interval to 24 hours, and returns to the main screen.
    @MainActor
    private func configureNotifications(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 3))
        app.staticTexts["Notifications"].tap()

        let toggle = app.switches["Enable reminder notifications"]
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
        app.buttons["Done"].tap()
    }

    @MainActor
    func testFullNotificationFlow() async throws {
        let app = launchApp(
            seedJSON: #"{"reminders":[{"title":"Buy groceries"},{"title":"Call mom"}]}"#,
            notificationsSeam: true)

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
            lastSchedule?.contains("id=com.alanvardy.SingleThread.idle-reminder") == true,
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
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Notifications"].waitForExistence(timeout: 3))
        app.staticTexts["Notifications"].tap()

        let persistedToggle = app.switches["Enable reminder notifications"]
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
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Test"}]}"#)
        XCTAssertTrue(app.staticTexts["Test"].waitForExistence(timeout: 5))

        app.buttons["Settings"].tap()
        app.staticTexts["Notifications"].tap()

        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait])
    }
}
