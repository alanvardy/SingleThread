//
//  SingleThreadUITestsAppearanceLaunchTests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-20.
//

import XCTest

final class SingleThreadUITestsAppearanceLaunchTests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Deterministic cold-launch check: the app must foreground under XCTest and
    /// render a scene (not SpringBoard). The `--no-reminders` flag suppresses the
    /// Reminders TCC prompt that would otherwise stall scene activation on a fresh
    /// install. The appearance *value* is proven by the mapping unit test in
    /// `SingleThreadTests/AppearanceModeTests.swift` and the activation application
    /// is proven by the `SimVerify: app active` log; this test proves the app became
    /// active and is visually the app scene, not SpringBoard.
    @MainActor
    func testColdLaunchAppearance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--no-reminders"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 2),
            "App should reach its content scene and render text (not SpringBoard)")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SimVerify cold launch (--no-reminders)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
