import Foundation
import SingleThreadCore
import Testing

struct ExcludedListStoreTests {
    @Test
    func loadDefaultsAndRoundTrips() {
        let store = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        #expect(store.load().isEmpty, "empty by default")
        store.save(["Work", "Personal"])
        #expect(Set(store.load()) == ["Work", "Personal"], "round-trips titles")
        store.save(["C"])
        #expect(Set(store.load()) == ["C"], "save replaces, not unions")
        store.save([])
        #expect(store.load().isEmpty, "save([]) clears")
    }

    @Test
    func storesAreIsolatedByKey() {
        let first = ExcludedListStore(defaults: .standard, key: "test-iso-1-\(UUID().uuidString)")
        let second = ExcludedListStore(defaults: .standard, key: "test-iso-2-\(UUID().uuidString)")
        first.save(["Work"])
        #expect(second.load().isEmpty, "key A write never visible to key B")
    }
}
