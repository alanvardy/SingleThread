//
//  SingleThreadUITests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // App skips reminders access in UI testing mode, showing a
        // ProgressView with "Requesting access…". Wait for any visible
        // text element before auditing.
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 5),
            "App should display text content")

        // Audit accessibility for key categories; skip contrast (known
        // false-positive source for system colors) and textClipped.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
