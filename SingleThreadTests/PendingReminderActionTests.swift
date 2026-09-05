import Foundation
import SingleThreadCore
import Testing

/// Covers the `PendingReminderAction` Codable codec and the single-slot
/// `PendingReminderActionStore` mailbox used to hand Complete/Skip off from the
/// watch widget process to the watch app.
struct PendingReminderActionTests {
    // MARK: Internal

    @Test
    func codableRoundTrip() throws {
        let action = PendingReminderAction(kind: .complete, identifier: "rem-42")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PendingReminderAction.self, from: data)
        #expect(decoded == action)
    }

    @Test
    func storeRoundTripsSaveAndLoad() {
        let defaults = isolatedDefaults("roundtrip")
        let store = PendingReminderActionStore(defaults: defaults)
        store.save(PendingReminderAction(kind: .skip, identifier: "rem-7"))
        #expect(store.load() == PendingReminderAction(kind: .skip, identifier: "rem-7"))
    }

    @Test
    func storeClearsSavedAction() {
        let defaults = isolatedDefaults("clear")
        let store = PendingReminderActionStore(defaults: defaults)
        store.save(PendingReminderAction(kind: .complete, identifier: "rem-7"))
        store.clear()
        #expect(store.load() == nil)
    }

    @Test
    func storeLoadsNilWhenEmpty() {
        let defaults = isolatedDefaults("empty")
        #expect(PendingReminderActionStore(defaults: defaults).load() == nil)
    }

    // MARK: Private

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suite = "PendingReminderActionTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
