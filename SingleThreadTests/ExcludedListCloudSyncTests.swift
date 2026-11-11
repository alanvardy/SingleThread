import Foundation
import SingleThreadCore
import Testing

/// The iCloud apply path: persist to the App Group, fire the WatchConnectivity
/// push hook, and never echo back into the key-value store. `ReminderStore` is
/// `@MainActor`, so the suite is too (same shape as `ReminderStoreTests`).
@MainActor
struct ExcludedListCloudSyncTests {
    @Test
    func applyCloudExcludedListTitlesPersistsAppGroupAndFiresHook() {
        let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)")
        let backing = InMemoryUbiquitousStore()
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: excludeStore,
            cloudStore: ExcludedListCloudStore(store: backing, key: "test-cloud-\(UUID().uuidString)"),
            loadsReminders: false)
        var changedTitles: [String]?
        var pushCount = 0
        var remindersChanged = false
        store.onExcludedListsChanged = { changedTitles = $0; pushCount += 1 }
        store.onRemindersChanged = { remindersChanged = true }

        store.applyCloudExcludedListTitles(["Work", "Personal"])

        #expect(store.excludedListTitles == ["Work", "Personal"])
        #expect(Set(excludeStore.load()) == ["Work", "Personal"])
        #expect(Set(changedTitles ?? []) == ["Work", "Personal"])
        #expect(pushCount == 1)
        #expect(remindersChanged)
        #expect(backing.values.isEmpty)
    }

    @Test
    func applyCloudExcludedListTitlesNeverWritesCloudStore() {
        let backing = InMemoryUbiquitousStore()
        let cloudKey = "test-cloud-\(UUID().uuidString)"
        let cloudStore = ExcludedListCloudStore(store: backing, key: cloudKey)
        cloudStore.save(["Work"])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            excludeStore: ExcludedListStore(defaults: .standard, key: "test-excluded-\(UUID().uuidString)"),
            cloudStore: cloudStore,
            loadsReminders: false)

        store.applyCloudExcludedListTitles(["Personal"])

        #expect(store.excludedListTitles == ["Personal"])
        #expect(cloudStore.load() == ["Work"])
    }

    @Test
    func identicalCloudValueIsIgnored() {
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: ["Work"], local: ["Work"]) == nil)
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: nil, local: ["Work"]) == nil)
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: ["Work", "Home"], local: ["Work"]) == ["Work", "Home"])
        #expect(ExcludedListCloudStore.titlesToAdopt(cloud: [], local: ["Work"])?.isEmpty == true)
    }
}

#if os(iOS) || os(macOS)
    @testable import SingleThread

    /// Serialized: `--ui-testing` builds an App-Group-backed store, so the
    /// excluded-list key is written on the real suite and must be cleaned up.
    @MainActor
    @Suite(.serialized)
    struct ExcludedListCloudObserverWiringTests {
        @Test
        func externalCloudChangeAdoptsIntoStoreAndAppGroup() async throws {
            let appGroupKey = ExcludedListStore.defaultsKey
            AppGroup.defaults.removeObject(forKey: appGroupKey)
            defer { AppGroup.defaults.removeObject(forKey: appGroupKey) }
            let backing = InMemoryUbiquitousStore()
            let cloudStore = ExcludedListCloudStore(
                store: backing,
                key: ExcludedListCloudStore.defaultsKey)
            let appViewModel = AppViewModel(
                arguments: ["--ui-testing", "--ui-testing-noop-settle"],
                cloudStore: cloudStore)
            let store = appViewModel.store

            // Another device pushes a new set, then iCloud posts the change.
            cloudStore.save(["Work"])
            NotificationCenter.default.post(
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: nil)

            // The observer hops through `Task { @MainActor in … }`; pump until the
            // adopted value lands, bounded so a regression cannot hang the run.
            var attempts = 0
            while store.excludedListTitles.isEmpty, attempts < 50 {
                try await Task.sleep(for: .milliseconds(20))
                attempts += 1
            }

            #expect(store.excludedListTitles == ["Work"])
            #expect(Set(ExcludedListStore().load()) == ["Work"])
        }
    }
#endif
