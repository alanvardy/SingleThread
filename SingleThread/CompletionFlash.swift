import Foundation
import Observation

/// A transient flag that tints the complete toolbar item green for a moment
/// after a successful completion. Mirrors ``SingleThreadCore/CompletionGlow``'s
/// trigger / auto-dismiss shape but owns no overlay — the toolbar item reads
/// `isActive` directly. The duration matches the dictation success indicator
/// (``CreationFeedback/displayDuration``) so both confirmations land on the
/// same beat.
@MainActor
@Observable
final class CompletionFlash {
    // MARK: Internal

    /// `true` while the complete item should render green.
    private(set) var isActive = false

    /// Seconds the tint stays on. Injectable for tests (e.g. 0.05 s); defaults
    /// to the dictation checkmark's on-screen time.
    var duration: TimeInterval = CreationFeedback.displayDuration

    /// Turns the tint on, resetting the auto-dismiss timer if already active.
    func trigger() {
        isActive = true
        dismissTask?.cancel()
        let seconds = duration
        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                self?.isActive = false
            } catch {
                // Cancelled by a newer trigger — that trigger owns the timer.
            }
        }
    }

    // MARK: Private

    private var dismissTask: Task<Void, Never>?
}
