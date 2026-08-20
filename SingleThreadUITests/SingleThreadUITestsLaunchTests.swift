//
//  SingleThreadUITestsLaunchTests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITestsLaunchTests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot override it.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
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
