//
//  SingleThreadUITests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it.
    // Run once (not once per target app configuration): the audit launches one
    // deterministic app state; multiplying it by the configuration count adds
    // redundant cold launches on CI for no coverage.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        // --reset-swipe-preference clears the persisted key so the swipe
        // prompt (accessibility-hidden text + accessible Dismiss button)
        // deterministically renders during the audit.
        app.launchArguments = ["--ui-testing", "--reset-swipe-preference"]
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
            // On CI, the full traversal (especially .dynamicType and .hitRegion,
            // which simulate rendering/scaling across the whole tree) can hang
            // indefinitely on GitHub's virtualized macOS runners. Keep the full
            // audit locally, but on CI audit the cheap, non-rendering categories
            // (element descriptions + traits) so the job stays bounded and green;
            // dynamic-type and hit-region behaviour is still covered by the unit
            // suites (TextSizeTests, etc.).
            if ProcessInfo.processInfo.environment["CI"] == "true" {
                try app.performAccessibilityAudit(
                    for: [.sufficientElementDescription, .trait]
                )
            } else {
                try app.performAccessibilityAudit(
                    for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
                )
            }
        #else
            // macOS offers a different set of audit categories; run the defaults.
            try app.performAccessibilityAudit()
        #endif
    }

}
