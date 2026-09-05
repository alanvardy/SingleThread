import CoreGraphics

/// Pure, viewport-relative cap for content cards, shared by the empty states
/// and the reminder card. Returns `min(ceiling, fraction)` so cards hug short
/// content but never balloon on wide (iPad) screens. Kept free of SwiftUI so
/// unit tests can pin the math without rendering.
///
/// `maxContentWidth` is `nonisolated` so the pure math stays pinnable from
/// nonisolated test contexts — the app target defaults all declarations to
/// `MainActor` isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION`).
enum CardWidth {
    nonisolated static func maxContentWidth(viewportWidth: CGFloat) -> CGFloat {
        min(340, viewportWidth * 0.6)
    }
}
