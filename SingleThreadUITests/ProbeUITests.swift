import XCTest

final class ProbeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProbeClusterState() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        var report = ""
        for (label, delay) in [("t1", 1), ("t4", 4)] {
            sleep(UInt32(delay))
            let mic = app.buttons["dictateButton"].exists
            let micLabel = mic ? (app.buttons["dictateButton"].label) : "nomic"
            report += "[\(label)] mic=\(mic) label=\(micLabel) complete=\(app.buttons["completeButton"].exists) card=\(app.staticTexts["Buy groceries"].exists)\n"
        }
        XCTAssertFalse(true, "PROBE_REPORT\n" + report)
    }
}