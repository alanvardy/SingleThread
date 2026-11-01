import Foundation
import Sentry

/// Allow-list scrubber applied to every event and breadcrumb before send.
/// It strips every free-text field that could carry reminder/list content and
/// keeps only structural metadata (exception type, allow-listed tags, and
/// breadcrumb category/level/timestamp).
/// Returns `nil` to drop a breadcrumb when its payload is not allow-listed.
enum SentryScrubber {
    /// One frame reduced to the fields `beforeSend` actually receives.
    struct StackFrameSignature: Equatable {
        /// `Frame.package` — the loaded binary's path.
        let image: String
        /// `Frame.inApp`, with the app-bundle path as a belt-and-braces fallback.
        let isApp: Bool
    }

    /// Tag keys that carry app/device metadata only — never reminder content.
    nonisolated static let allowedTags: Set<String> = ["environment", "release", "level"]

    /// Binary-image substrings of the synchronous BackBoardServices/backlight XPC
    /// stall UIKit performs on the main thread. Sentry issue 7821993169:
    /// `BKSDisplayBrightnessGetCurrent` (BackBoardServices) →
    /// `bootstrap_look_up` (libxpc).
    ///
    /// Function names are NOT available in `beforeSend` — sentry-cocoa sets only
    /// `package`/`inApp` at capture and symbolicates `function` server-side — so
    /// the signature is matched on image paths.
    nonisolated static let systemStallSignatureImages: [String] = [
        "BackBoardServices",
        "libxpc.dylib"
    ]

    /// Pure drop decision. Fail-open: any under-specified input returns `false`,
    /// so the event is reported rather than silently lost.
    ///
    /// All three conditions must hold:
    ///  1. the mechanism is the public, stable `"AppHang"` marker,
    ///  2. the stack contains every image in `systemStallSignatureImages`,
    ///  3. no in-app frame sits at or deeper than the first stall frame.
    nonisolated static func isSystemStall(
        mechanismType: String?,
        frames: [StackFrameSignature]) -> Bool {
        guard mechanismType == "AppHang" else { return false }
        guard !frames.isEmpty else { return false }
        guard systemStallSignatureImages.allSatisfy({ signature in
            frames.contains { $0.image.contains(signature) }
        }) else { return false }
        guard let firstStall = frames.firstIndex(where: { frame in
            systemStallSignatureImages.contains { frame.image.contains($0) }
        }) else { return false }
        return !frames[firstStall...].contains(where: \.isApp)
    }

    /// Reduces a Sentry event to an app-hang signature, or `nil` for any shape it
    /// does not recognise (fail-open).
    nonisolated static func appHangStack(
        in event: Event) -> (mechanismType: String, frames: [StackFrameSignature])? {
        guard
            let exception = event.exceptions?.first(where: {
                $0.mechanism?.type == "AppHang"
            }),
            let mechanismType = exception.mechanism?.type,
            let stacktrace = exception.stacktrace,
            !stacktrace.frames.isEmpty
        else { return nil }
        return (mechanismType, stacktrace.frames.map(StackFrameSignature.init))
    }

    nonisolated static func scrub(_ event: Event) -> Event? {
        if let stack = appHangStack(in: event),
           isSystemStall(mechanismType: stack.mechanismType, frames: stack.frames) {
            return nil
        }
        event.user = nil
        event.extra = nil
        event.request = nil
        event.modules = nil
        event.message = nil
        event.transaction = nil
        event.tags = event.tags?.filter { allowedTags.contains($0.key) }
        // `Exception.value` is free text (an uncaught `NSException`'s reason on
        // Apple platforms); keep the structural `type` so crashes still group.
        event.exceptions?.forEach { $0.value = nil }
        event.breadcrumbs = event.breadcrumbs?.compactMap(scrub)
        return event
    }

    /// Keeps category/level/timestamp, drops the free-text message and data bag.
    /// The `data` setter is deprecated in sentry-cocoa (it becomes read-only), so a
    /// clean breadcrumb is rebuilt with only the structural fields.
    nonisolated static func scrub(_ breadcrumb: Breadcrumb) -> Breadcrumb? {
        let scrubbed = Breadcrumb(level: breadcrumb.level, category: breadcrumb.category)
        scrubbed.timestamp = breadcrumb.timestamp
        return scrubbed
    }
}

extension SentryScrubber.StackFrameSignature {
    nonisolated init(_ frame: Frame) {
        let image = frame.package ?? ""
        self.image = image
        isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")
    }
}
