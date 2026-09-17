//
//  SingleThreadUITests.swift
//  SingleThreadUITests
//
//  Created by Alan Vardy on 2026-08-12.
//

import XCTest

final class SingleThreadUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it. Run once (not once per target app configuration): the smoke
    // launches one deterministic app state; multiplying it by the configuration
    // count adds redundant cold launches on CI for no coverage.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndRenderSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Plain --ui-testing seeds one reminder ("Buy groceries" /
        // "Don't forget the milk", priority 5 → "!!") with
        // enableActionButtons ON, so the card + Complete/Skip/mic cluster render.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Reminder title should render")
        XCTAssertTrue(app.staticTexts["Don't forget the milk"].exists,
                      "Reminder notes should render")
        XCTAssertTrue(app.staticTexts["priorityMarker"].exists,
                      "Priority marker \"!!\" should render")
        // The action cluster is a separate async region below the card; on a
        // cold first launch (fresh simulator) it can lag the card by a beat, so
        // wait for it like the title does (mirrors the pre-collapse Flows
        // pattern, `complete.waitForExistence(timeout: 3)`).
        XCTAssertTrue(
            app.buttons["completeButton"].waitForExistence(timeout: 5),
            "Complete action should render")
        XCTAssertTrue(app.buttons["skipButton"].exists,
                      "Skip action should render")
        XCTAssertTrue(app.buttons["dictateButton"].exists,
                      "Dictate action should render")

        // Fold the CI-parity a11y audit into the smoke check, using the cheap,
        // non-rendering categories only. .dynamicType/.hitRegion can hang on
        // GitHub's virtualized runners and are covered by unit suites
        // (TextSizeTests etc.), so they are deliberately excluded — matching the
        // former CI carve-out, now applied everywhere (local and CI alike).
        #if os(iOS)
            try app.performAccessibilityAudit(
                for: [.sufficientElementDescription, .trait]
            )
        #else
            // macOS's audit API offers a different category set, so the smoke
            // can't use the iOS categories there. The smoke only runs on the
            // iOS Simulator; this branch exists so the UI-test bundle still
            // compiles for the macOS test phase.
            try app.performAccessibilityAudit()
        #endif
    }

    /// End-to-end language flow: the settings sheet's Interface screen starts in
    /// the system (English test) locale, then switching the picker to Deutsch
    /// re-localizes the presented screen's own label with no relaunch. This is
    /// the only place any unit test could not observe: the environment-locale
    /// propagation through the presented sheet and its pushed row is a SwiftUI
    /// runtime behavior.
    @MainActor
    func testLanguageSelectionChangesVisibleString() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5),
                      "Settings gear should render")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsInterfaceRow"].waitForExistence(timeout: 5),
                      "Interface row should render")
        app.buttons["settingsInterfaceRow"].tap()

        // English baseline, then switch to Deutsch.
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5),
                      "English Appearance label should render first")
        app.buttons["languagePicker"].tap()
        // The picker presents its options asynchronously; wait for the German
        // option (matching any element type, since menu rows may surface as
        // buttons or static texts) so the tap doesn't race the presentation.
        let deutsch = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Deutsch")).firstMatch
        XCTAssertTrue(deutsch.waitForExistence(timeout: 5),
                      "German option should appear in the language picker")
        deutsch.tap()

        // The Interface screen's own label re-localizes with no relaunch.
        XCTAssertTrue(
            app.staticTexts["Darstellung"].waitForExistence(timeout: 5),
            "Appearance label should re-localize to German after selection")
        XCTAssertFalse(app.staticTexts["Appearance"].exists)
        // The navigation title must re-localize too. SwiftUI resolves a
        // LocalizedStringKey navigationTitle once against the system language,
        // so this is the regression that motivated `localizedNavigationTitle`.
        XCTAssertTrue(
            app.navigationBars["Oberfläche"].waitForExistence(timeout: 5),
            "Navigation title should re-localize to German after selection")
        XCTAssertFalse(app.navigationBars["Interface"].exists)

        // Back at the settings root, its title must have re-localized too — the
        // symptom reported as "Settings stayed in Japanese until I reopened the
        // sheet".
        app.navigationBars["Oberfläche"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(
            app.navigationBars["Einstellungen"].waitForExistence(timeout: 5),
            "Root Settings title should re-localize to German without reopening the sheet")
        XCTAssertFalse(app.navigationBars["Settings"].exists)

        // A second change in the same session must also stick — the navigation
        // bar must not freeze after its first update.
        app.buttons["settingsInterfaceRow"].tap()
        XCTAssertTrue(app.staticTexts["Darstellung"].waitForExistence(timeout: 5),
                      "Interface screen should still render in German")
        app.buttons["languagePicker"].tap()
        let english = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "English")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5),
                      "English option should appear in the language picker")
        english.tap()
        XCTAssertTrue(app.navigationBars["Interface"].waitForExistence(timeout: 5),
                      "Navigation title should re-localize back to English")
        app.navigationBars["Interface"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Root title should follow a second language change")
    }

    /// Sad path: an unsupported stored raw value degrades to `.system`, so the
    /// system (English) test-locale labels render instead of falling into a
    /// stale or broken language.
    @MainActor
    func testUnsupportedStoredLanguageFallsBackToSystem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-app-language", "klingon"]
        app.launch()
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 5),
                      "Settings gear should render")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsInterfaceRow"].waitForExistence(timeout: 5),
                      "Interface row should render")
        app.buttons["settingsInterfaceRow"].tap()
        // `.system` under the (English) test locale → the source labels render.
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5),
                      "Appearance should render from the system locale")
    }
}
