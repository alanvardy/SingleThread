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
        app.launch()

        // Dismiss any system permission dialogs that appear.
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            if alert.buttons["Allow"].exists {
                alert.buttons["Allow"].tap()
                return true
            }
            alert.buttons.firstMatch.tap()
            return true
        }
        // Trigger the interruption monitor by interacting with the app.
        app.tap()

        // Audit accessibility for key categories; skip contrast (known
        // false-positive source for system colors) and textClipped.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait]
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
