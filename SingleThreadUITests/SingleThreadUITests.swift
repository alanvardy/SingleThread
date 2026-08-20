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

        // With --ui-testing, the app instantiates an empty store
        // (loadsReminders: false), so the view renders the "No Reminders"
        // empty reminderList branch. Wait for any visible text element before
        // auditing.
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 2),
            "App should display text content")

        // Audit accessibility for key categories; skip contrast (known
        // false-positive source for system colors) and textClipped.
        #if os(iOS)
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
            )
        #else
            // macOS offers a different set of audit categories; run the defaults.
            try app.performAccessibilityAudit()
        #endif
    }

}
