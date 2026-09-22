import Foundation
@testable import SingleThread
import SingleThreadCore
import Testing

@MainActor
struct SortOptionTests {
    @Test
    func rawValuesMatchPayloadKeys() {
        #expect(SortOption.default.rawValue == "default")
        #expect(SortOption.priority.rawValue == "priority")
        #expect(SortOption.dueDate.rawValue == "dueDate")
        #expect(SortOption.title.rawValue == "title")
        #expect(SortOption.ai.rawValue == "ai")
    }

    @Test
    func allCasesCoverAllOptions() {
        #expect(SortOption.allCases == [.default, .priority, .dueDate, .title, .ai])
    }

    /// AI sort is disabled: the menu offers every case except `.ai`, and the
    /// disabled case reports itself unselectable so the store and sync guard it.
    @Test
    func menuOptionsWithholdTheDisabledAIOption() {
        #expect(SortOption.menuOptions == [.default, .priority, .dueDate, .title])
        #expect(SortOption.default.isSelectable)
        #expect(!SortOption.ai.isSelectable)
        #expect(SortOption.priority.isSelectable)
        #expect(SortOption.dueDate.isSelectable)
        #expect(SortOption.title.isSelectable)
    }

    @Test
    func defaultsKeyIsTheSharedConstant() {
        #expect(SortOption.defaultsKey == "sortOption")
    }

    @Test
    func presentationTitlesAreHumanReadable() {
        #expect(
            SortOption.default.title.resolved(in: Locale(identifier: "en")) == "Default")
        #expect(
            SortOption.priority.title.resolved(in: Locale(identifier: "en"))
                == String.en("Priority", bundle: .main))
        #expect(
            SortOption.dueDate.title.resolved(in: Locale(identifier: "en"))
                == String.en("Due Date", bundle: .main))
        #expect(
            SortOption.title.title.resolved(in: Locale(identifier: "en"))
                == String.en("Title", bundle: .main))
        #expect(
            SortOption.ai.title.resolved(in: Locale(identifier: "en"))
                == String.en("AI", bundle: .main))
    }

    @Test
    func presentationSystemImagesAreValidSFSymbols() {
        #expect(!SortOption.default.systemImage.isEmpty)
        #expect(!SortOption.priority.systemImage.isEmpty)
        #expect(!SortOption.dueDate.systemImage.isEmpty)
        #expect(!SortOption.title.systemImage.isEmpty)
        #expect(!SortOption.ai.systemImage.isEmpty)
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

    /// `.default` is offered by the menu, so it must round-trip through the
    /// store without being coerced back to the `.priority` fallback.
    @Test
    func saveAndLoadRoundTripsDefault() {
        let key = "test-sort-roundtrip-default-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = SortOptionStore(defaults: .standard, key: key)
        store.save(.default)
        #expect(store.load() == .default)
    }

    /// A value persisted before AI sort was disabled must not keep ranking: it
    /// degrades to `.priority` on read, so the picker is never handed a
    /// selection it cannot offer.
    @Test
    func loadDegradesDisabledAIOptionToPriority() {
        let key = "test-sort-disabled-ai-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(SortOption.ai.rawValue, forKey: key)
        let store = SortOptionStore(defaults: .standard, key: key)
        #expect(store.load() == .priority)
    }

    @Test
    func saveNeverPersistsDisabledAIOption() {
        let key = "test-sort-save-ai-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = SortOptionStore(defaults: .standard, key: key)
        store.save(.ai)
        #expect(UserDefaults.standard.string(forKey: key) == SortOption.priority.rawValue)
        #expect(store.load() == .priority)
    }
}
