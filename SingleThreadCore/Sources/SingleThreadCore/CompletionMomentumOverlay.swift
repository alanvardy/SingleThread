import Foundation

/// A transient overlay shown after a reminder is completed, displaying
/// "You've cleared N today". Owned by `ContentViewModel` and triggered
/// alongside `CompletionGlow` when a completion succeeds.
///
/// The overlay auto-dismisses: `trigger(count:)` sets `isActive = true` and
/// records the count, then after `duration` seconds a non-blocking task sets
/// `isActive` back to `false`. Re-triggering while active resets the timer.
///
/// Default duration is 2.0 s — longer than `CompletionGlow`'s 0.5 s so the
/// text is readable before it fades.
@MainActor
@Observable
public final class CompletionMomentumOverlay {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// `true` while the overlay should be visible in the view.
    public private(set) var isActive = false

    /// The count displayed while active (snapshotted at trigger time).
    public private(set) var todayCount = 0

    /// Seconds the overlay stays visible before auto-dismissing.
    /// Injectable for tests; default 2.0 s.
    public var duration: TimeInterval = 2.0

    /// Shows the overlay with the given count, resetting the auto-dismiss
    /// timer if already active. Calling this multiple times in quick
    /// succession keeps the overlay visible for the most recent `duration`
    /// from the last trigger.
    public func trigger(count: Int) {
        todayCount = count
        isActive = true
        dismissTask?.cancel()
        let seconds = duration
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.isActive = false
            } catch {
                // Cancelled by a newer trigger — that trigger owns the timer,
                // so leave `isActive` untouched.
            }
        }
    }

    // MARK: Private

    private var dismissTask: Task<Void, Never>?
}
