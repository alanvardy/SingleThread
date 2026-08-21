import Foundation

/// Guards a one-shot `Checked*Continuation` resume so competing resume sources
/// (a framework callback and a timeout, or two deliveries) never double-resume.
public final class ResumptionGate: @unchecked Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var hasResumed = false
}

/// Hops onto the MainActor and calls `resume`, which performs the actual
/// `continuation.resume`. Routes the success/return resume through this one
/// route. Must be `nonisolated` so it can be invoked from an off-main completion
/// queue; it only schedules a `Task` that returns to main and never touches
/// isolated state.
public nonisolated func resumeOnMainActor(_ gate: ResumptionGate, _ resume: @escaping @Sendable () -> Void) {
    Task { @MainActor in
        guard !gate.hasResumed else { return }
        gate.hasResumed = true
        resume()
    }
}
