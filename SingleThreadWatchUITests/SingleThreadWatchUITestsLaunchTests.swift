import XCTest

final class SingleThreadWatchUITestsLaunchTests: XCTestCase {
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
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Watch Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}