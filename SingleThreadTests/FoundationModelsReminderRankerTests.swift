@testable import SingleThread
import Testing

/// Deterministic under any host/CI: the assertions never invoke the model,
/// only compare the ranker's own availability surface for self-consistency.
struct FoundationModelsReminderRankerTests {
    @Test
    func availabilityGateMatchesIsAvailable() {
        #expect(
            FoundationModelsReminderRanker.isAvailable
                == (FoundationModelsReminderRanker.availability == .available))
    }
}
