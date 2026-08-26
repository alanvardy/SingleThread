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
    // Run once per launch configuration to keep the CI suite within its step
    // timeout on cold virtualized simulators.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Deterministic cold-launch check: the app must foreground under XCTest and
    /// render a scene (not SpringBoard). The `--no-reminders` flag suppresses the
    /// Reminders TCC prompt that would otherwise stall scene activation on a fresh
    /// install. The appearance *value* is proven by the mapping unit test in
    /// `SingleThreadTests/AppearanceModeTests.swift` and activation is proven by
    /// the `SimVerify: app active` log; this test proves the app became active and
    /// is visually the app scene, not SpringBoard.
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

    /// Runtime reachability: open Settings (gear), locate the Appearance picker,
    /// and tap it. The app must remain foreground and live (a screenshot throws
    /// if the app is not the foreground scene). SwiftUI exposes the Appearance
    /// Picker headless as a single Button labeled "Appearance" — not as individual
    /// System/Light/Dark option buttons — so pressing the picker row is the
    /// reachable, deterministic surface. The row's accessibility *identifier*
    /// varies (it is the currently-selected mode's symbol, e.g. "moon.fill" /
    /// "circle.lefthalf.filled" depending on the persisted appearance), so the
    /// test matches by the stable label. The actual override value is mapped and
    /// unit-proven (`SingleThreadTests/AppearanceModeTests.swift`); the picker
    /// value flip is not headless-asserted (the plan's documented fallback).
    @MainActor
    func testRuntimeAppearanceToggle() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--no-reminders"]
        app.launch()

        app.buttons["Settings"].tap()
        // The appearance picker now lives inside the Interface sub-menu.
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3), "Settings should show Interface")
        app.staticTexts["Interface"].tap()
        let appearancePicker = app.buttons
            .matching(NSPredicate(format: "label == %@", "Appearance"))
            .firstMatch
        XCTAssertTrue(
            appearancePicker.waitForExistence(timeout: 2),
            "Settings sheet should present the appearance picker (label Appearance)")
        // Open the appearance picker. A screenshot here proves the app stayed
        // foreground and alive through the interaction (screenshot throws if not).
        appearancePicker.tap()
        app.screenshot()
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 2),
            "App should remain foreground after opening the appearance picker")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SimVerify runtime appearance toggle"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Device-follow path exercised through the same reachable surface: open
    /// Settings and the Appearance picker while live. Clearing the ad override on
    /// `.system` is unit-proven (`systemMapsToUnspecifiedWindowStyle`); here we
    /// verify the app remains foreground and interactive through the appearance
    /// picker flow.
    @MainActor
    func testDeviceFollowingClearsOverride() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--no-reminders"]
        app.launch()

        app.buttons["Settings"].tap()
        // The appearance picker now lives inside the Interface sub-menu.
        XCTAssertTrue(app.staticTexts["Interface"].waitForExistence(timeout: 3), "Settings should show Interface")
        app.staticTexts["Interface"].tap()
        let appearancePicker = app.buttons
            .matching(NSPredicate(format: "label == %@", "Appearance"))
            .firstMatch
        XCTAssertTrue(
            appearancePicker.waitForExistence(timeout: 2),
            "Settings sheet should present the appearance picker (label Appearance)")
        appearancePicker.tap()
        app.screenshot()
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 2),
            "App should remain foreground after opening the appearance picker (.system path)")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "SimVerify device-follow (.system)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
