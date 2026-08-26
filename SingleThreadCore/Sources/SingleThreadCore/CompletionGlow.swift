import Foundation

/// A transient full-screen green flash shown briefly after a reminder is
/// completed. Both the iOS and watch view models own an instance and
/// trigger it when completion succeeds. The duration is injectable so
/// tests can shrink it to near-zero.
///
/// The glow auto-dismisses: `trigger()` sets `isActive = true`, then
/// after `duration` seconds a non‑blocking task sets it back to `false`.
/// Triggering while active is safe — the timer resets.
@MainActor
@Observable
public final class CompletionGlow {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// `true` while the green overlay should be visible in the view.
    public private(set) var isActive = false

    /// Seconds the glow stays visible before auto‑dismissing.
    /// Injectable for tests (e.g. 0.05 s); default 0.25 s.
    public var duration: TimeInterval = 0.25

    /// Shows the glow, resetting the auto‑dismiss timer if already active.
    /// Calling this multiple times in quick succession keeps the glow
    /// visible for the most recent `duration` from the last trigger.
    public func trigger() {
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
