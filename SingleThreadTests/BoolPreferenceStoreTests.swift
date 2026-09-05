import Foundation
import SingleThreadCore
import Testing

struct BoolPreferenceStoreTests {
    // MARK: Internal

    // MARK: — Absent-key fallback

    @Test(arguments: allPairs)
    func absentValueFallsBackToConfiguredDefault(_ pair: (String, Bool)) {
        let key = "test-absent-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(store.isEnabled == pair.1)
    }

    // MARK: — Round-trip

    @Test(arguments: allPairs)
    func roundTripTrue(_ pair: (String, Bool)) {
        let key = "test-rtt-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(true)
        #expect(store.isEnabled == true)
    }

    @Test(arguments: allPairs)
    func roundTripFalse(_ pair: (String, Bool)) {
        let key = "test-rf-\(UUID().uuidString)-\(pair.0)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: pair.1)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(false)
        #expect(store.isEnabled == false)
    }

    // MARK: — Overwrite

    @Test
    func setOverwritesPreviousValue() {
        let key = "test-overwrite-\(UUID().uuidString)"
        let store = BoolPreferenceStore(defaults: .standard, key: key, fallback: true)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.set(true)
        store.set(false)
        #expect(store.isEnabled == false)
    }

    // MARK: — Injection

    @Test
    func customDefaultsInjection() throws {
        let suiteName = "test-custom-\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store1 = BoolPreferenceStore(defaults: suite, key: "k", fallback: false)
        let store2 = BoolPreferenceStore(defaults: .standard, key: "k", fallback: true)
        store1.set(true)
        #expect(store2.isEnabled == true) // .standard never got written
    }

    // MARK: Private

    /// Every (key, fallback) pair from the six old structs.
    private static let allPairs: [(key: String, fallback: Bool)] = [
        ("showDate", true),
        ("showRecurrence", true),
        ("showAlarms", true),
        ("showCompletionGlow", true),
        ("showList", false),
        ("showUndatedReminders", false)
    ]
}
