import XCTest

/// Shared base for all iOS UI tests: one launch path (seed vs --ui-testing),
/// one toggle-flip helper, and one persistence-relaunch verifier.
class SingleThreadUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Single launch entry point. `--seed` for deterministic write flows;
    /// `--ui-testing` for persistence-across-relaunch (seed resets the key).
    @MainActor
    func launchApp(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    @MainActor
    func launchSeeded(_ json: String, extra: [String] = []) -> XCUIApplication {
        launchApp(arguments: ["--seed", json] + extra)
    }

    /// SwiftUI Form rows expose a nested switch; tap the inner control until
    /// it flips. Shared by flows/notifications/scheduling suites.
    @MainActor
    func flipToggle(_ toggle: XCUIElement, target: String = "0") -> Bool {
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

    /// Relaunch with `--ui-testing` and assert a settings toggle kept its value.
    @MainActor
    func assertTogglePersists(
        toggleID: String, settingsRowID: String, expectedValue: String, message: String) {
        let relaunched = launchApp(arguments: ["--ui-testing"])
        XCTAssertTrue(relaunched.buttons["settingsButton"].waitForExistence(timeout: 5))
        relaunched.buttons["settingsButton"].tap()
        XCTAssertTrue(relaunched.buttons[settingsRowID].waitForExistence(timeout: 3))
        relaunched.buttons[settingsRowID].tap()
        let toggle = relaunched.switches[toggleID]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, expectedValue, message)
    }

    /// Reads an app-side seam status element's label. The UI-test runner cannot
    /// query the app's own notification store, so assertions read the pending /
    /// last-schedule snapshots the app exposes under `--ui-testing-notifications`.
    @MainActor
    func statusLabel(_ app: XCUIApplication, identifier: String) -> String? {
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
}
