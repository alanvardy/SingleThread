import Foundation

/// Presentation state for the single-reminder watch card.
///
/// The Digital Crown on watchOS can only drive one control at a time: while the
/// card is expanded, a `ScrollView` owns the crown for reading long titles/notes,
/// so crown‑triggered refresh is disabled. Collapsing hands the crown back to
/// the refresh gesture.
public struct WatchReminderPresentation: Equatable, Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public private(set) var isExpanded = false

    /// Whether the Digital Crown drives refresh (collapsed) rather than
    /// scrolling (expanded).
    public var allowsCrownRefresh: Bool {
        !isExpanded
    }

    public mutating func toggle() {
        isExpanded.toggle()
    }
}
