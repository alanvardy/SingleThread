import EventKit
@testable import SingleThreadCore
import Testing

// The Undo completion suite keeps this file above the `file_length` warning
// threshold (650); the shared file-scoped `makeReminder` fixtures require the
// suites to live together.
// swiftlint:disable file_length

/// No-op settle hook: deterministic and sleep-free. Injected as the
/// `ReminderStore` `settle:` seam so skip-path tests don't pay a real wait.
private let noopSettle: ReminderStoreSettle = {}

@MainActor
@Suite(.serialized)
struct ReminderStoreTests {
    // MARK: - visibleReminders

    @Test
    func visibleRemindersFiltersSkippedAndEmpty() {
        let rem = makeReminder(title: "A")
        let other = makeReminder(title: "B")
        let filtered = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem, other],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let visible = filtered.visibleReminders
        #expect(visible.count == 1, "one non-skipped reminder remains visible")
        #expect(visible.first?.title == "B", "the skipped reminder is filtered out")

        let allSkipped = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(allSkipped.visibleReminders.isEmpty, "empty when every reminder is skipped")

        let empty = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(empty.visibleReminders.isEmpty, "empty when there are no reminders")
    }

    @Test
    func visibleRemindersSortsByPriorityThenDate() {
        let low = makeReminder(title: "low", priority: 9)
        let high = makeReminder(title: "high", priority: 1)
        let byPriority = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [low, high],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(byPriority.visibleReminders.map(\.title) == ["high", "low"], "higher priority sorts first")

        let undated = makeReminder(title: "undated", priority: 5)
        let dated = makeReminder(
            title: "dated",
            priority: 5,
            dateComponents: DateComponents(year: 2024, month: 1, day: 1))
        let byDate = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [undated, dated],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(byDate.visibleReminders.map(\.title) == ["dated", "undated"], "dated sorts before undated")
    }

    @Test
    func visibleRemindersFiltersExcludedListTitles() {
        let excluded = makeReminder(title: "A", calendarTitle: "Work")
        let kept = makeReminder(title: "B", calendarTitle: "Personal")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [excluded, kept],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(store.visibleReminders.map(\.title) == ["B"], "reminders in excluded lists are filtered")

        let noCalendar = makeReminder(title: "A") // calendar == nil
        let keepsNil = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [noCalendar],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(keepsNil.visibleReminders.count == 1, "nil-calendar reminders are never excluded")

        let inList = makeReminder(title: "A", calendarTitle: "Work")
        let allExcluded = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [inList],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(allExcluded.visibleReminders.isEmpty, "empty when every list is excluded")
    }

    // MARK: - availableLists

    @Test
    func availableListsDefaultsToEmpty() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(store.availableLists.isEmpty)
    }

    // MARK: - setExcludedListTitles

    @Test
    func setExcludedListTitlesPersistsAndFiresHooks() {
        let key = "test-excluded-\(UUID().uuidString)"
        let excludeStore = ExcludedListStore(defaults: .standard, key: key)
        let store = ReminderStore(eventStore: InMemoryEventStore(), excludeStore: excludeStore, loadsReminders: false)
        var changedTitles: [String]?
        var remindersChanged = false
        store.onExcludedListsChanged = { changedTitles = $0 }
        store.onRemindersChanged = { remindersChanged = true }

        store.setExcludedListTitles(["Work", "Personal"])

        #expect(store.excludedListTitles == ["Work", "Personal"])
        #expect(Set(excludeStore.load()) == ["Work", "Personal"])
        #expect(Set(changedTitles ?? []) == ["Work", "Personal"])
        #expect(remindersChanged)
    }

    // MARK: - refreshExcludedListTitles

    @Test
    func refreshExcludedListTitlesUpdatesSetAndFiresRemindersChangedOnly() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var remindersChanged = false
        var excludedChanged = false
        store.onRemindersChanged = { remindersChanged = true }
        store.onExcludedListsChanged = { _ in excludedChanged = true }

        store.refreshExcludedListTitles(["Work"])

        #expect(store.excludedListTitles == ["Work"])
        #expect(remindersChanged)
        #expect(!excludedChanged)
    }

    // MARK: - setSortOption

    @Test
    func setSortOptionReordersAndNotifies() {
        let highLater = makeReminder(
            title: "HighLater",
            priority: 1,
            dateComponents: DateComponents(year: 2024, month: 1, day: 10))
        let lowSooner = makeReminder(
            title: "LowSooner",
            priority: 9,
            dateComponents: DateComponents(year: 2024, month: 1, day: 2))
        let reorderStore = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [lowSooner, highLater],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(
            reorderStore.visibleReminders.map(\.title) == ["HighLater", "LowSooner"],
            "default sort option is .priority")
        reorderStore.setSortOption(.dueDate)
        #expect(
            reorderStore.visibleReminders.map(\.title) == ["LowSooner", "HighLater"],
            "dueDate option reorders visible reminders")

        let hookStore = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "A")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var received: SortOption?
        var remindersChanged = false
        hookStore.onSortOptionChanged = { received = $0 }
        hookStore.onRemindersChanged = { remindersChanged = true }
        hookStore.setSortOption(.title)
        #expect(received == .title, "sort-option hook fires with the new option")
        #expect(remindersChanged, "reminders-changed hook fires")

        let idempotent = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        var fired = 0
        idempotent.onSortOptionChanged = { _ in fired += 1 }
        idempotent.setSortOption(.title)
        idempotent.setSortOption(.title)
        idempotent.setSortOption(.title)
        #expect(fired == 1, "three identical sets notify exactly once")
    }

    // MARK: - addReminder

    @Test
    func addReminderSucceedsAndKeepsExistingReminders() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "Existing")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let added = await store.addReminder(title: "New", notes: nil, dueDate: nil)
        #expect(added, "add returns true when the save succeeds")
        #expect(store.reminders.count == 1, "existing reminders untouched")
        #expect(store.reminders.first?.title == "Existing", "the pre-seeded reminder is retained")

        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        let withRule = await store.addReminder(
            title: "Weekly review",
            notes: nil,
            dueDate: DateComponents(year: 2025, month: 1, day: 1),
            recurrenceRule: rule)
        #expect(withRule, "add succeeds when a recurrence rule is provided")
    }

    // MARK: - skipCurrentReminder

    @Test
    func skipCurrentReminderNoOpsAndNotifies() async {
        let empty = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        empty.skipCurrentReminder()
        #expect(empty.skippedIDs.isEmpty, "no visible reminders → skipped set unchanged")

        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.onSkipSetChanged = { _ in continuation.resume() }
            store.skipCurrentReminder()
        }
        #expect(store.skippedIDs.contains(rem.calendarItemIdentifier), "the visible reminder's id is skipped")

        let hookStore = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "B")],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            hookStore.onRemindersChanged = { continuation.resume() }
            hookStore.skipCurrentReminder()
        }
        // Resuming the continuation proves the reminders-changed hook fired.
    }

    @Test
    func skipCurrentReminderRefetchesAndDropsCompletedReminder() async {
        let remA = makeReminder(title: "A", priority: 1)
        let remB = makeReminder(title: "B", priority: 9)
        remB.isCompleted = true // "completed on another device"
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [remA, remB]),
            loadsReminders: true,
            reminders: [remA, remB],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: noopSettle)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // `onRemindersChanged` fires once from `applySkipSet` and once when
            // the follow-up `reload()` finishes — resume on the second fire so
            // `reminders` is the refetched set when assertions run below.
            var fires = 0
            store.onRemindersChanged = {
                fires += 1
                if fires >= 2 {
                    continuation.resume()
                }
            }
            store.skipCurrentReminder() // skip A (sorts first)
        }

        #expect(store.skippedIDs.contains(remA.calendarItemIdentifier))
        #expect(!store.reminders.contains { $0 === remB }) // B dropped by refetch
    }

    @Test
    func skipCurrentReminderRefetchKeepsSkippedReminder() async {
        let remA = makeReminder(title: "A", priority: 1)
        let remB = makeReminder(title: "B", priority: 9)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [remA, remB]),
            loadsReminders: true,
            reminders: [remA, remB],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: noopSettle)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Same two-fire rendezvous as the sibling test above: the second
            // `onRemindersChanged` call means the skip Task's `reload()` finished.
            var fires = 0
            store.onRemindersChanged = {
                fires += 1
                if fires >= 2 {
                    continuation.resume()
                }
            }
            store.skipCurrentReminder()
        }

        #expect(store.skippedIDs.contains(remA.calendarItemIdentifier))
        #expect(store.reminders.contains { $0 === remB }) // incomplete → still fetched
        #expect(store.visibleReminders.map(\.title) == ["B"]) // A hidden by skip only
    }

    @Test
    func skipCurrentReminderDiscardedAfterClearSkipped() async {
        let rem = makeReminder(title: "A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            loadsReminders: true,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            settle: noopSettle)

        store.skipCurrentReminder()
        // The awaited clear reload bumps the skip generation and empties the set.
        // The in-flight skip Task either applied before the bump (its skip is
        // then wiped by the clear) or attempts to apply after it (discarded by
        // the generation gate) — both end with an empty skipped set, so no
        // additional wait is needed.
        await store.reload(clearSkipped: true)

        #expect(store.skippedIDs.isEmpty)
        #expect(store.visibleReminders.count == 1) // reminder visible again — skip not re-applied
    }

    // MARK: - completeCurrentReminder

    @Test
    func completeCurrentReminderCompletesVisibleAndNoOpsOtherwise() async {
        let none = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let completedNone = await none.completeCurrentReminder()
        #expect(!completedNone, "no reminders → nothing to complete")

        let rem = makeReminder(title: "A")
        let allSkipped = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let completedSkipped = await allSkipped.completeCurrentReminder()
        #expect(!completedSkipped, "all skipped → nothing visible to complete")
        #expect(allSkipped.reminders.count == 1, "skipped completion leaves reminders untouched")

        let visibleStore = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let completedVisible = await visibleStore.completeCurrentReminder()
        #expect(completedVisible, "visible reminder completes")
        #expect(rem.isCompleted, "the visible reminder is marked completed")
    }

    // MARK: - completeReminder

    @Test
    func completeReminderDoesNothingWhenIdentifierNotFound() async {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        let completed = await store.completeReminder(identifier: "nonexistent")
        #expect(!completed)
    }

    // MARK: - start / reload guards

    @Test
    func lifecycleGuardsRespectLoadsRemindersFlag() async {
        let offMain = InMemoryEventStore(
            reminders: [makeReminder(title: "A")],
            deliverCompletionOffMain: true)
        let fetching = ReminderStore(eventStore: offMain, loadsReminders: true)
        await fetching.reload()
        #expect(
            fetching.reminders.map(\.title) == ["A"],
            "reload resumes on the main actor when the fetch completes off-main")

        let masked = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        #expect(masked.showsUndatedReminders == false, "showsUndatedReminders defaults to false")
        await masked.start()
        #expect(masked.authorizationStatus == .notDetermined, "start no-ops when loadsReminders false")
        await masked.reload()
        #expect(masked.reminders.isEmpty, "reload no-ops when loadsReminders false")
        await masked.reload(clearSkipped: true)
        #expect(masked.reminders.isEmpty, "reload(clearSkipped:) no-ops when loadsReminders false")
    }

    // MARK: - hasHidden

    @Test
    func hasHiddenReflectsSeedsAndSets() {
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!store.hasHidden, "defaults to false")
        let seeded = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            hasHidden: true)
        #expect(seeded.hasHidden, "seeds from init when hasHidden is passed")

        let reminder = makeReminder(title: "A")
        #expect(
            !ReminderStore.hasHiddenFor(shown: [reminder], allIncomplete: [reminder]),
            "false when shown and all-incomplete sets match")
        let hidden = makeReminder(title: "Hidden")
        #expect(
            ReminderStore.hasHiddenFor(shown: [hidden], allIncomplete: [hidden, reminder]),
            "true when an incomplete reminder is hidden")
    }

    // MARK: - allSkipped

    @Test
    func allSkippedReflectsState() {
        let rem = makeReminder(title: "A")
        let allSkipped = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [rem.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        #expect(allSkipped.allSkipped, "true when reminders exist but all are skipped")
        let empty = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!empty.allSkipped, "false when there are no reminders")
        let visible = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
        #expect(!visible.allSkipped, "false when a visible reminder exists")
        let excluded = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [makeReminder(title: "A", calendarTitle: "Work")],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        #expect(excluded.allSkipped, "true when every reminder is in an excluded list")
    }
}

// MARK: - Undo completion

#if !os(watchOS)
    @MainActor
    @Suite(.serialized)
    struct UndoCompletionTests {
        @Test
        func completeRetainsInUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(store.undoStore.hasUndoableReminder)
            #expect(store.undoStore.lastCompletedReminder === rem)
        }

        @Test
        func undoLastCompletionRevertsReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(rem.isCompleted)
            let undone = await store.undoLastCompletion()
            #expect(undone)
            #expect(!rem.isCompleted)
        }

        @Test
        func undoLastCompletionClearsUndoStore() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            _ = await store.undoLastCompletion()
            #expect(!store.undoStore.hasUndoableReminder)
        }

        @Test
        func secondCompleteOverwritesUndoStore() async {
            let remA = makeReminder(title: "A")
            let remB = makeReminder(title: "B")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [remA, remB],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            _ = await store.completeReminder(identifier: remA.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remA)
            _ = await store.completeReminder(identifier: remB.calendarItemIdentifier)
            #expect(store.undoStore.lastCompletedReminder === remB)
            // Undo B — A is gone permanently
            _ = await store.undoLastCompletion()
            #expect(!remB.isCompleted)
            #expect(remA.isCompleted) // A stays completed
        }

        @Test
        func undoReturnsFalseWhenNoRetainedReminder() async {
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoReturnsFalseWhenGated() async {
            let key = UUID().uuidString
            UserDefaults.standard.set(100, forKey: key)
            let counter = CompletionCounterStore(defaults: .standard, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter,
                entitlementStore: EntitlementStore(testingWithEntitled: false))
            // Manually stash a reminder (simulating a prior completion before
            // the gate closed; the complete itself would have been gated).
            store.undoStore.retain(rem)
            let undone = await store.undoLastCompletion()
            #expect(!undone)
        }

        @Test
        func undoDecrementsCompletionCounter() async {
            let key = UUID().uuidString
            let defaults = UserDefaults.standard
            let counter = CompletionCounterStore(defaults: defaults, key: key)
            let rem = makeReminder(title: "A")
            let store = ReminderStore(
                eventStore: InMemoryEventStore(),
                loadsReminders: false,
                reminders: [rem],
                skippedIDs: [],
                authorizationStatus: .fullAccess,
                completionCounter: counter)
            _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
            #expect(counter.count == 1)
            _ = await store.undoLastCompletion()
            #expect(counter.count == 0) // swiftlint:disable:this empty_count
        }
    }
#endif

// MARK: - reload pending + defensive filter

/// Returns every seeded reminder verbatim — including completed ones — so the
/// defensive `!isCompleted` filter in `reload()` can be exercised (unlike
/// `InMemoryEventStore`, which filters `!isCompleted` before it reaches the store).
@MainActor
private final class CompletedReturningEventStore: EventKitStoring {
    // MARK: Lifecycle

    init(fetchResult: [EKReminder]) {
        self.fetchResult = fetchResult
    }

    // MARK: Internal

    let fetchResult: [EKReminder]

    func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus {
        .fullAccess
    }

    func calendars(for _: EKEntityType) -> [EKCalendar] {
        []
    }

    func requestFullAccessToReminders() async throws -> Bool {
        true
    }

    func predicateForIncompleteReminders(
        withDueDateStarting _: Date?,
        ending _: Date?,
        calendars _: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
    }

    @discardableResult
    func fetchReminders(matching _: NSPredicate, completion: @escaping ([EKReminder]?) -> Void) -> Any {
        completion(fetchResult)
        return ()
    }

    #if !os(watchOS)
        func refreshSourcesIfNecessary() {}
        func save(_: EKReminder, commit _: Bool) throws {}
        func remove(_: EKReminder, commit _: Bool) throws {}
        func makeReminder(
            title _: String,
            notes _: String?,
            dueDate _: DateComponents?,
            recurrenceRule _: EKRecurrenceRule?) -> EKReminder {
            EKReminder(eventStore: sharedTestEventStore)
        }
    #endif
}

@MainActor
@Suite(.serialized)
struct ReloadPendingCompletionTests {
    // MARK: Internal

    @Test
    func reloadFiltersPendingCompletions() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let remA = makeReminder(title: "A")
        let remB = makeReminder(title: "B")
        pendingStore(key: key).save([remB.calendarItemIdentifier])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [remA, remB]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [remA, remB],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // B pending → hidden
    }

    @Test
    func reloadPrunesStalePendingCompletions() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let remA = makeReminder(title: "A")
        pendingStore(key: key).save(["stale-id"]) // id no longer in the fetch
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [remA]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [remA],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // not pending → visible
        #expect(pendingStore(key: key).load().isEmpty) // stale-id pruned from set + persisted
    }

    @Test
    func reloadKeepsPendingWhenStillFetched() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let remA = makeReminder(title: "A")
        let remB = makeReminder(title: "B")
        pendingStore(key: key).save([remB.calendarItemIdentifier])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [remA, remB]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [remA, remB],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // still hidden
        #expect(pendingStore(key: key).load() == [remB.calendarItemIdentifier]) // still incomplete → stays
    }

    @Test
    func reloadWithEmptyFetchPreservesPendingCompletions() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let seeded = "still-pending-id"
        pendingStore(key: key).record(seeded)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: []),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(pendingStore(key: key).load() == [seeded]) // not wiped by empty fetch
    }

    @Test
    func reloadDefensivelyDropsCompletedReminder() async {
        let completed = makeReminder(title: "Done")
        completed.isCompleted = true
        let fake = CompletedReturningEventStore(fetchResult: [completed])
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = ReminderStore(
            eventStore: fake,
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true)

        await store.reload()

        #expect(store.reminders.isEmpty)
    }

    // MARK: Private

    private func pendingStore(key: String) -> PendingCompletionStore {
        PendingCompletionStore(defaults: .standard, key: key)
    }
}

// MARK: - makeReminder test seam

#if !os(watchOS)
    @MainActor
    struct MakeReminderTests {
        @Test
        func makeReminderSetsTitle() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.title == "Buy milk")
        }

        @Test
        func makeReminderSetsNotes() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: "Two percent",
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.notes == "Two percent")
        }

        @Test
        func makeReminderSetsDueDate() {
            let dueDate = DateComponents(year: 2025, month: 1, day: 2)
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: dueDate,
                recurrenceRule: nil)
            #expect(reminder.dueDateComponents?.year == dueDate.year)
            #expect(reminder.dueDateComponents?.month == dueDate.month)
            #expect(reminder.dueDateComponents?.day == dueDate.day)
        }

        @Test
        func makeReminderLeavesUnsetFieldsNil() {
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.notes == nil)
            #expect(reminder.dueDateComponents == nil)
            #expect(reminder.hasRecurrenceRules == false)
        }

        @Test
        func makeReminderSetsRecurrenceRule() {
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
            let reminder = InMemoryEventStore().makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: rule)
            #expect(reminder.recurrenceRules?.count == 1)
            #expect(reminder.recurrenceRules?.first?.frequency == .weekly)
            #expect(reminder.recurrenceRules?.first?.interval == 1)
        }

        @Test
        func makeReminderUsesDefaultCalendar() {
            let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
            calendar.title = "Custom"
            let store = InMemoryEventStore(calendars: [], defaultCalendar: calendar)
            let reminder = store.makeReminder(
                title: "Test",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.calendar == calendar)
        }

        /// Tests real EventKit calendar behavior — intentionally uses EKEventStore.
        @Test
        func makeReminderSetsDefaultCalendar() {
            let eventStore = EKEventStore()
            let reminder = (eventStore as any EventKitStoring).makeReminder(
                title: "Buy milk",
                notes: nil,
                dueDate: nil,
                recurrenceRule: nil)
            #expect(reminder.calendar == eventStore.defaultCalendarForNewReminders())
        }
    }
#endif

// MARK: - Fixtures

@MainActor private let sharedTestEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String, priority: Int = 0, dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
private func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}
