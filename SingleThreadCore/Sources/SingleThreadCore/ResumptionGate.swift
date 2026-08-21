import Foundation

/// Guards a one-shot `Checked*Continuation` resume so competing resume sources
/// (a framework callback and a timeout, or two deliveries) never double-resume.
///
/// SAFETY INVARIANT (why `@unchecked Sendable` is sound): `hasResumed` is
/// written and read only on the main actor, entirely inside `Task { @MainActor
/// in … }` bodies (`resumeOnMainActor` here, and the terminal resume branches in
/// `ReminderDictation.awaitFinalResult`). The MainActor is a serial executor, so
/// no two writes can observe `false` and both proceed; `tryResume` does the
/// check-and-set atomically on that actor with no `await` in between. The flag
/// itself never crosses a thread.
///
/// REMOVAL PLAN: replace the `Bool` with a `ManagedAtomic<Bool>`/`Mutex`-backed
/// one-shot token so the single-resume invariant is enforced inside the gate
/// itself rather than by the caller's actor discipline, then delete
/// `@unchecked Sendable`. Until then, mutate `hasResumed` only through
/// `tryResume` on the main actor.
public final class ResumptionGate: @unchecked Sendable {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// Whether a resume source has already claimed the gate. Read-only to
    /// callers; mutate only via `tryResume` (on the main actor).
    public private(set) var hasResumed = false

    /// Claims the gate for the caller. Returns `true` only for the first
    /// caller, `false` for any later (competing) resume source, which should
    /// then skip its resume. Must be called on the main actor (SAFETY
    /// INVARIANT); no `await` separates the check from the store.
    public func tryResume() -> Bool {
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

/// Hops onto the MainActor and calls `resume`, which performs the actual
/// `continuation.resume`. Routes the success/return resume through this one
/// route. Must be `nonisolated` so it can be invoked from an off-main completion
/// queue; the invoked closure and the gate are only ever touched back on the
/// main actor, never on the queue.
public nonisolated func resumeOnMainActor(_ gate: ResumptionGate, _ resume: @escaping @Sendable () -> Void) {
    Task { @MainActor in
        guard gate.tryResume() else { return }
        resume()
    }
}
