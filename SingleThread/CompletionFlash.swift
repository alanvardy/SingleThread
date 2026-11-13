import Foundation
import Observation
import SingleThreadCore

/// A transient flag that tints the complete toolbar item green for a moment
/// after a successful completion. Mirrors ``SingleThreadCore/CompletionGlow``'s
/// trigger / auto-dismiss shape but owns no overlay — the toolbar item reads
/// `isActive` directly. The duration matches the green screen flash
/// (``CompletionGlow``) so the icon and the flash land on the same beat.
@MainActor
@Observable
final class CompletionFlash {
    // MARK: Internal

    /// `true` while the complete item should render green.
    private(set) var isActive = false

    /// Seconds the tint stays on. Injectable for tests (e.g. 0.05 s); defaults
    /// to the green screen flash's on-screen time so the icon's green lasts
    /// exactly as long as the flash.
    var duration: TimeInterval = CompletionGlow().duration

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
