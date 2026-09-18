import Foundation
import SingleThreadCore
import Testing

struct AISortRulesStoreTests {
    @Test
    func loadsEmptyDefaultWhenMissing() {
        let store = AISortRulesStore(
            defaults: .standard,
            key: "test-ai-rules-missing-\(UUID().uuidString)")
        #expect(store.load().isEmpty)
    }

    @Test
    func saveAndLoadRoundTrip() {
        let key = "test-ai-rules-roundtrip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = AISortRulesStore(defaults: .standard, key: key)
        store.save("clients first")
        #expect(store.load() == "clients first")
    }

    @Test
    func defaultsKeyIsAISortRules() {
        #expect(AISortRulesStore.defaultsKey == "aiSortRules")
    }
}
