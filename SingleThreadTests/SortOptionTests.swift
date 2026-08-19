import Foundation
import SingleThreadCore
import Testing

struct SortOptionTests {
    @Test
    func rawValuesMatchPayloadKeys() {
        #expect(SortOption.priority.rawValue == "priority")
        #expect(SortOption.dueDate.rawValue == "dueDate")
        #expect(SortOption.title.rawValue == "title")
    }

    @Test
    func allCasesCoverAllOptions() {
        #expect(SortOption.allCases == [.priority, .dueDate, .title])
    }

    @Test
    func defaultsKeyIsTheSharedConstant() {
        #expect(SortOption.defaultsKey == "sortOption")
    }
}

struct SortOptionStoreTests {
    @Test
    func loadsPriorityDefaultWhenMissing() {
        let store = SortOptionStore(defaults: .standard, key: "test-sort-missing-\(UUID().uuidString)")
        #expect(store.load() == .priority)
    }

    @Test
    func loadsPriorityDefaultWhenInvalid() {
        let key = "test-sort-invalid-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set("notAValue", forKey: key)
        let store = SortOptionStore(defaults: .standard, key: key)
        #expect(store.load() == .priority)
    }

    @Test
    func saveAndLoadRoundTrip() {
        let key = "test-sort-roundtrip-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = SortOptionStore(defaults: .standard, key: key)
        store.save(.dueDate)
        #expect(store.load() == .dueDate)
    }
}
