import Foundation
import Sentry
@testable import SingleThread
import Testing

struct SentryScrubberTests {
    // MARK: Internal

    @Test
    func reminderContentIsRemovedFromEvent() {
        let event = Event()
        event.extra = ["reminderTitle": "Buy milk", "note": "2%"]
        event.user = User(userId: "Buy milk")
        event.tags = ["reminderTitle": "Buy milk", "environment": "debug"]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
        #expect(scrubbed?.tags?["reminderTitle"] == nil)
        #expect(scrubbed?.tags?["environment"] == "debug") // allow-listed field survives
    }

    @Test
    func reminderContentIsRemovedFromBreadcrumb() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")
        breadcrumb.message = "Buy milk from the Grocery list"
        breadcrumb.setData(value: "2%", key: "note")
        breadcrumb.setData(value: "Grocery", key: "listName")

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.data == nil)
        #expect(scrubbed?.category == "reminder") // benign structural field survives
    }

    @Test
    func eventWithoutTagsStaysClean() {
        let event = Event()

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed != nil)
        #expect(scrubbed?.extra == nil)
        #expect(scrubbed?.user == nil)
    }

    @Test
    func breadcrumbWithoutDataSurvives() {
        let breadcrumb = Breadcrumb(level: .info, category: "reminder")

        let scrubbed = SentryScrubber.scrub(breadcrumb)

        #expect(scrubbed != nil)
        #expect(scrubbed?.category == "reminder")
        #expect(scrubbed?.data == nil)
    }

    @Test
    func exceptionReasonIsRemovedButTypeSurvives() {
        let event = Event()
        event.exceptions = [Exception(
            value: "Buy milk from the Grocery list",
            type: "NSInternalInconsistencyException")]

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.exceptions?.first?.value == nil)
        #expect(scrubbed?.exceptions?.first?.type == "NSInternalInconsistencyException")
    }

    @Test
    func eventMessageAndTransactionAreRemoved() {
        let event = Event()
        event.message = SentryMessage(formatted: "Buy milk from the Grocery list")
        event.transaction = "reminder.detail"

        let scrubbed = SentryScrubber.scrub(event)

        #expect(scrubbed?.message == nil)
        #expect(scrubbed?.transaction == nil)
    }

    // MARK: App-hang system-stall predicate

    @Test
    func dropsCapturedBacklightSystemStall() {
        #expect(SentryScrubber.scrub(hangEvent(frames: Self.capturedFrames)) == nil)
    }

    @Test
    func keepsHangWithAppFrameInBlockedChain() {
        var frames = Self.capturedFrames
        let leaf = frames.count - 1
        frames[leaf] = (Self.appImage, true) // app is the blocked (deepest) frame
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func keepsNonHangBacklightEvent() {
        let event = hangEvent(frames: Self.capturedFrames, mechanismType: "Crash")
        event.extra = ["reminderTitle": "Buy milk"]
        let scrubbed = SentryScrubber.scrub(event)
        #expect(scrubbed != nil) // not dropped
        #expect(scrubbed?.extra == nil) // PII scrubbing still runs
    }

    // MARK: Fail-open guarantee

    @Test
    func keepsEventWhenMechanismRenamed() {
        #expect(SentryScrubber.scrub(hangEvent(
            frames: Self.capturedFrames, mechanismType: "AppHangRenamed")) != nil)
    }

    @Test
    func keepsEventWhenStacktraceMissing() {
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: "AppHang")
        event.exceptions = [exception]
        #expect(SentryScrubber.scrub(event) != nil)
    }

    @Test
    func keepsEventWhenFrameListEmpty() {
        #expect(SentryScrubber.scrub(hangEvent(frames: [])) != nil)
    }

    @Test
    func keepsEventWhenDenylistPartiallyMatches() {
        // BackBoardServices present, libxpc absent ⇒ not the backlight XPC stall.
        let frames = Self.capturedFrames.filter { $0.image != Self.libXPC }
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func keepsEventWhenAppFrameIsInBlockedChain() {
        var frames = Self.capturedFrames
        frames.insert((Self.appImage, true), at: frames.count) // app frame at the leaf
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    @Test
    func keepsEventWhenFramePackageIsMissing() {
        let frames = Self.capturedFrames.map { (image: "", inApp: $0.inApp) }
        #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
    }

    // MARK: Private

    // MARK: Fixtures

    private static let appImage =
        "/private/var/containers/Bundle/Application/277152F6-B99C-4FA0-BADB-098D8D06EC13/SingleThread.app/SingleThread"
    private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
    private static let uiKit = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
    private static let graphicsServices =
        "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices"
    private static let coreFoundation =
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
    private static let libDispatch = "/usr/lib/system/libdispatch.dylib"
    private static let backBoard =
        "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices"
    private static let libXPC = "/usr/lib/system/libxpc.dylib"
    private static let libObjCMsgSend = "/usr/lib/objc/libobjcMsgSend.dylib"

    /// The raw event's client-side exception stack (`package` + `in_app`), verbatim.
    private static let capturedFrames: [(image: String, inApp: Bool)] = [
        ("dyld", false),
        (appImage, true),
        (swiftUI, false), (swiftUI, false), (swiftUI, false),
        (uiKit, false), (graphicsServices, false),
        (coreFoundation, false), (coreFoundation, false), (coreFoundation, false),
        (libDispatch, false), (libDispatch, false), (libDispatch, false), (libDispatch, false),
        (coreFoundation, false), (coreFoundation, false),
        (uiKit, false), (uiKit, false), (uiKit, false),
        (backBoard, false), (backBoard, false),
        (libXPC, false), (libXPC, false), (libXPC, false), (libXPC, false), (libXPC, false),
        (libObjCMsgSend, false)
    ]

    private func hangEvent(
        frames: [(image: String, inApp: Bool)],
        mechanismType: String = "AppHang") -> Event {
        let event = Event()
        let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
        exception.mechanism = Mechanism(type: mechanismType)
        exception.stacktrace = SentryStacktrace(frames: frames.map { frame in
            let sentryFrame = Frame()
            sentryFrame.package = frame.image
            // Sentry's `Frame.inApp` is SDK-mandated NSNumber.
            // swiftlint:disable:next legacy_objc_type
            sentryFrame.inApp = NSNumber(value: frame.inApp)
            return sentryFrame
        }, registers: [:])
        event.exceptions = [exception]
        return event
    }
}
