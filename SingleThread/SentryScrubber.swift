import Foundation
import Sentry

/// Allow-list scrubber applied to every event and breadcrumb before send.
/// Returns `nil` to drop a breadcrumb when its payload is not allow-listed.
enum SentryScrubber {
    /// Tag keys that carry app/device metadata only — never reminder content.
    nonisolated static let allowedTags: Set<String> = ["environment", "release", "level"]

    nonisolated static func scrub(_ event: Event) -> Event? {
        event.user = nil
        event.extra = nil
        event.request = nil
        event.modules = nil
        event.tags = event.tags?.filter { allowedTags.contains($0.key) }
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
