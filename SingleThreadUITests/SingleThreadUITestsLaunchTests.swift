//
//  SingleThreadUITestsLaunchTests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITestsLaunchTests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot override it.
    // Run once (not once per target app configuration): on cold CI simulators the
    // launch test is slow, and multiplying it by the number of configurations
    // pushes the whole UI suite past its step timeout.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Launch through the test seam so EventKit auth is never requested: a
        // real launch would hit the Reminders TCC prompt on a fresh simulator
        // (VAR-639), which can steal foreground and stall the test.
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
