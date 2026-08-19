import Foundation
import SingleThreadCore
import Testing

struct ExcludedProjectStoreTests {
    @Test
    func loadReturnsEmptyByDefault() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-empty-\(UUID().uuidString)")
        #expect(store.load().isEmpty)
    }

    @Test
    func saveRoundTripsTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-roundtrip-\(UUID().uuidString)")
        store.save(["Work", "Personal"])
        #expect(Set(store.load()) == ["Work", "Personal"])
    }

    @Test
    func saveReplacesExistingTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-replace-\(UUID().uuidString)")
        store.save(["A", "B"])
        store.save(["C"])
        #expect(Set(store.load()) == ["C"])
    }

    @Test
    func saveEmptyClearsTitles() {
        let store = ExcludedProjectStore(defaults: .standard, key: "test-excluded-clear-\(UUID().uuidString)")
        store.save(["A"])
        store.save([])
        #expect(store.load().isEmpty)
    }

    @Test
    func storesAreIsolatedByKey() {
        let first = ExcludedProjectStore(defaults: .standard, key: "test-excluded-isolation-1-\(UUID().uuidString)")
        let second = ExcludedProjectStore(defaults: .standard, key: "test-excluded-isolation-2-\(UUID().uuidString)")
        first.save(["Work"])
        #expect(second.load().isEmpty)
    }
}
