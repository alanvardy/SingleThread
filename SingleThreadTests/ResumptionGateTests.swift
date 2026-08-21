@testable import SingleThreadCore
import Testing

// MARK: - ResumptionGate

/// Verifies the one-shot single-resume semantics of `ResumptionGate`, the guard
/// shared by the off-main continuation hops (`ReminderDictation`, `ReminderStore`).
/// The gate must let exactly one competing resume source win and refuse all
/// subsequent ones, so a framework callback / timeout double-resume can never
/// trap.
@MainActor
@Suite(.serialized)
struct ResumptionGateTests {
    @Test
    func resolvesOnceAcrossMultipleClaimAttempts() {
        let gate = ResumptionGate()
        #expect(!gate.hasResumed)
        #expect(gate.tryResume())
        #expect(gate.hasResumed)
        #expect(!gate.tryResume(), "second claim must lose")
        #expect(!gate.tryResume(), "third claim must lose")
    }

    @Test
    func freshGateAllowsFirstClaim() {
        let gate = ResumptionGate()
        #expect(gate.tryResume())
        #expect(gate.tryResume() == false)
    }
}
