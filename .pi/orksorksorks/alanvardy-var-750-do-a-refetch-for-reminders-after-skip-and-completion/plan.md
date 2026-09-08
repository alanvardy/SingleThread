# Implementation Plan

## Overview

After every skip and watchOS completion, `ReminderStore` refetches from EventKit so completed reminders drop out of the list, with a persisted watch-side `pendingCompletions` set that `reload()` filters against until the phone processes the relay, plus a defensive `!isCompleted` filter at the end of every `reload()`.

All paths are relative to the repo root. Stages follow `structure.md` in order; each stage's gate must be green before the next begins.

---

## Stage 1: Persistence — `PendingCompletionStore`

### Changes

#### 1. New pending-completion store
**File**: `SingleThreadCore/Sources/SingleThreadCore/PendingCompletionStore.swift`
**Action**: create

Mirror `SkippedReminderStore` (`ReminderSkip.swift:119-138`), but backed by `Set<String>` (the value every consumer uses). `UserDefaults` cannot store `Set` directly, so serialize via `stringArray`.

```swift
import Foundation

/// Persists pending-completion reminder identifiers in UserDefaults. The watch
/// records a completed identifier here until the phone processes the relay and
/// the reminder stops appearing in incomplete fetches; `reload()` prunes it.
public struct PendingCompletionStore {
    // MARK: Lifecycle

    public init(
        defaults: UserDefaults = AppGroup.defaults,
        key: String = "pendingCompletionIdentifiers") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    public func load() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// Replaces the stored set — never unions. This invariant (a clear prunes
    /// stale IDs) is what lets `reload()` drain the set when the phone
    /// processes a relay.
    public func save(_ identifiers: Set<String>) {
        defaults.set(Array(identifiers), forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Unit tests
**File**: `SingleThreadTests/PendingCompletionStoreTests.swift`
**Action**: create

```swift
import Foundation
import SingleThreadCore
import Testing

struct PendingCompletionStoreTests {
    private func makeStore() -> (PendingCompletionStore, String) {
        let key = "pending-test-\(UUID().uuidString)"
        return (PendingCompletionStore(defaults: .standard, key: key), key)
    }

    @Test
    func loadDefaultsToEmptySet() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        #expect(store.load().isEmpty)
    }

    @Test
    func saveLoadRoundTrips() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.save(["a", "b"])
        #expect(store.load() == ["a", "b"])
    }

    @Test
    func saveReplacesPreviousValue() {
        let (store, key) = makeStore()
        defer { UserDefaults.standard.removeObject(forKey: key) }
        store.save(["a", "b"])
        store.save(["c"]) // second save drops prior IDs — no union
        #expect(store.load() == ["c"])
    }

    @Test
    func usesInjectedSuiteNotStandard() {
        let key = "pending-test-\(UUID().uuidString)"
        // Write via one suite, read via another — the injected suite must win.
        let storeA = PendingCompletionStore(defaults: AppGroup.defaults, key: key)
        let storeB = PendingCompletionStore(defaults: .standard, key: key)
        defer {
            AppGroup.defaults.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
        storeA.save(["x"])
        #expect(storeB.load().isEmpty) // .standard never saw the write
    }
}
```

### Verification

#### Automated
- [x] `make test` green (full iOS unit gate)
- [x] Targeted: `xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath DerivedData test -only-testing:SingleThreadTests/PendingCompletionStoreTests` (pin destination `,OS=<ver>` or `,id=<UDID>` per AGENTS.md — name-only hangs)

#### Manual
- [ ] No manual step — persistence is exercised end-to-end by Stages 5–6.

---

## Stage 2: Pure reconcile logic — `PendingCompletionLogic`

### Changes

#### 1. Pure filtering/pruning logic
**File**: `SingleThreadCore/Sources/SingleThreadCore/PendingCompletionLogic.swift`
**Action**: create

Stateless, side-effect-free (like `ReminderSkipLogic`). Reads `EKReminder.calendarItemIdentifier`/`isCompleted` — safe because every call site is `@MainActor` (`reload()`) or a `@MainActor` test; `EKReminder` is `@retroactive @unchecked Sendable` (`ReminderDateFilter.swift:23`).

```swift
import EventKit
import Foundation

/// Pure logic for the watch-side pending-completion set. No store access —
/// fully unit-testable in isolation.
public nonisolated enum PendingCompletionLogic {
    /// Drops reminders whose identifier is still pending (the phone has not
    /// yet processed the watch's relayed completion).
    public static func filtering(fetched: [EKReminder], pending: Set<String>) -> [EKReminder] {
        fetched.filter { !pending.contains($0.calendarItemIdentifier) }
    }

    /// Keeps only pending IDs that are still present in the fetch. IDs absent
    /// from `fetchedIdentifiers` have been completed by the phone and drain out.
    public static func pruned(pending: Set<String>, fetchedIdentifiers: Set<String>) -> Set<String> {
        pending.intersection(fetchedIdentifiers)
    }

    /// Defensive net: drops any completed reminder that slipped through the
    /// incomplete predicate.
    public static func removingCompleted(_ reminders: [EKReminder]) -> [EKReminder] {
        reminders.filter { !$0.isCompleted }
    }
}
```

#### 2. Unit tests
**File**: `SingleThreadTests/PendingCompletionLogicTests.swift`
**Action**: create

Reminders built via `InMemoryEventStore().makeReminder(title:notes:dueDate:recurrenceRule:)` (iOS-only `#if !os(watchOS)` — fine, this is the iOS unit target).

```swift
import EventKit
@testable import SingleThreadCore
import Testing

@MainActor
struct PendingCompletionLogicTests {
    private func reminder(_ title: String, completed: Bool = false) -> EKReminder {
        let store = InMemoryEventStore()
        let rem = store.makeReminder(title: title, notes: nil, dueDate: nil, recurrenceRule: nil)
        rem.isCompleted = completed
        return rem
    }

    @Test
    func filteringDropsPendingIdentifiers() {
        let a = reminder("A"), b = reminder("B")
        let out = PendingCompletionLogic.filtering(fetched: [a, b], pending: [a.calendarItemIdentifier])
        #expect(out.map(\.title) == ["B"])
    }

    @Test
    func filteringKeepsNonPending() {
        let a = reminder("A"), b = reminder("B")
        let out = PendingCompletionLogic.filtering(fetched: [a, b], pending: ["other"])
        #expect(out.count == 2)
    }

    @Test
    func prunedKeepsOnlyFetchedIDs() {
        let out = PendingCompletionLogic.pruned(pending: ["a", "b", "c"], fetchedIdentifiers: ["b", "c", "d"])
        #expect(out == ["b", "c"])
    }

    @Test
    func prunedEmptiesWhenNothingFetched() {
        #expect(PendingCompletionLogic.pruned(pending: ["a"], fetchedIdentifiers: []).isEmpty)
    }

    @Test
    func removingCompletedDropsCompletedOnly() {
        let done = reminder("Done", completed: true)
        let todo = reminder("Todo")
        let out = PendingCompletionLogic.removingCompleted([done, todo])
        #expect(out.map(\.title) == ["Todo"])
    }
}
```

### Verification

#### Automated
- [x] `make test` green
- [x] Targeted: `xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath DerivedData test -only-testing:SingleThreadTests/PendingCompletionLogicTests`

#### Manual
- [ ] No manual step — pure logic, fully unit-covered.

---

## Stage 3: `reload()` integration — filter, prune, defend

### Changes

#### 1. Store gains pending state
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**Init** — add `pendingCompletionStore` (after `skipStore`) and `pendingCompletions` (after `skippedIDs`) parameters, both defaulted so existing call sites compile unchanged:

```swift
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        pendingCompletionStore: PendingCompletionStore = PendingCompletionStore(),
        excludeStore: ExcludedListStore = ExcludedListStore(),
        loadsReminders: Bool = true,
        reminders: [EKReminder] = [],
        skippedIDs: Set<String> = [],
        pendingCompletions: Set<String> = [],
        authorizationStatus: EKAuthorizationStatus = .notDetermined,
        excludedListTitles: Set<String> = [],
        hasHidden: Bool = false,
        completionCounter: CompletionCounterStore = CompletionCounterStore(),
        entitlementStore: EntitlementStore = EntitlementStore()) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.pendingCompletionStore = pendingCompletionStore
        self.excludeStore = excludeStore
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.pendingCompletions = pendingCompletions
        // … rest unchanged
    }
```

**Stored properties** — add next to `skipStore` / `skipGeneration`:

```swift
    private let pendingCompletionStore: PendingCompletionStore
    /// Watch-completed identifiers awaiting the phone's relay. Loaded/pruned
    /// inside `reload()`; mutated by the watchOS `completeReminder` branch.
    private var pendingCompletions: Set<String> = []
```

#### 2. `reload()` applies filter + prune + defensive net
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Change `let shown` → `var shown`, insert the pending filter + defensive filter immediately before `reminders = shown`, and append the prune after the skip-prune block:

```swift
        let fetched: [EKReminder] = await fetchReminders(matching: predicate)
        var shown = showsUndatedReminders
            ? fetched.filter { ReminderDateFilter.isInCurrentWindow($0.dueDateComponents?.date) }
            : fetched
        if showsUndatedReminders {
            hasHidden = Self.hasHiddenFor(shown: shown, allIncomplete: fetched)
        } else {
            // … unchanged broad-fetch hasHidden derivation …
        }
        // Pending completions (watch-relayed) hide their reminder until the
        // phone processes them; the defensive filter guarantees the invariant.
        pendingCompletions = pendingCompletionStore.load()
        shown = PendingCompletionLogic.filtering(fetched: shown, pending: pendingCompletions)
        shown = PendingCompletionLogic.removingCompleted(shown)
        reminders = shown
        availableLists = Set(
            eventStore.calendars(for: .reminder)
                .map(\.title)
                .filter { !$0.isEmpty })
            .sorted()
        if clearSkipped {
            clearSkippedState()
        } else {
            let resolved = ReminderSkipLogic.resolve(
                fetched: shown.map(\.calendarItemIdentifier),
                skipped: skipStore.load())
            skippedIDs = Set(resolved)
            excludedListTitles = Set(excludeStore.load())
            skipStore.save(resolved)
        }
        // Prune pending IDs no longer present in the fetch — the phone has
        // processed the relay and the reminder is now genuinely completed.
        let pruned = PendingCompletionLogic.pruned(
            pending: pendingCompletions,
            fetchedIdentifiers: Set(fetched.map(\.calendarItemIdentifier)))
        if pruned != pendingCompletions {
            pendingCompletions = pruned
            pendingCompletionStore.save(pruned)
        }
        onRemindersChanged?()
```

Post-condition (asserted in tests): `reminders.allSatisfy { !$0.isCompleted }`.

#### 3. Unit tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add a new `// MARK: - reload pending + defensive filter` suite. The defensive-filter case needs a fake whose `fetchReminders` returns a *completed* reminder — `InMemoryEventStore` already filters `!isCompleted` so it can't reach that path. Add a compact file-local fake (modeled on `FakeEventStore` in `EventKitStoringTests.swift`):

```swift
@MainActor
private final class CompletedReturningEventStore: EventKitStoring {
    init(fetchResult: [EKReminder]) { self.fetchResult = fetchResult }
    let fetchResult: [EKReminder]

    func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus { .fullAccess }
    func calendars(for _: EKEntityType) -> [EKCalendar] { [] }
    func requestFullAccessToReminders() async throws -> Bool { true }
    func predicateForIncompleteReminders(withDueDateStarting _: Date?, ending _: Date?, calendars _: [EKCalendar]?) -> NSPredicate {
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
        func makeReminder(title _: String, notes _: String?, dueDate _: DateComponents?, recurrenceRule _: EKRecurrenceRule?) -> EKReminder {
            EKReminder(eventStore: sharedTestEventStore)
        }
    #endif
}
```

The four reload cases (all `loadsReminders: true`, custom-key `PendingCompletionStore(defaults: .standard, key:)` injected via init so `load()` is deterministic, with `defer removeObject`):

```swift
@MainActor
@Suite(.serialized)
struct ReloadPendingCompletionTests {
    private func pendingStore(key: String) -> PendingCompletionStore {
        PendingCompletionStore(defaults: .standard, key: key)
    }

    @Test
    func reloadFiltersPendingCompletions() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let a = makeReminder(title: "A")
        let b = makeReminder(title: "B")
        pendingStore(key: key).save([b.calendarItemIdentifier])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [a, b]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [a, b],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // B pending → hidden
    }

    @Test
    func reloadPrunesStalePendingCompletions() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let a = makeReminder(title: "A")
        pendingStore(key: key).save(["stale-id"]) // id no longer in the fetch
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [a]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [a],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // not pending → visible
        #expect(pendingStore(key: key).load().isEmpty) // stale-id pruned from set + persisted
    }

    @Test
    func reloadKeepsPendingWhenStillFetched() async {
        let key = "pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let a = makeReminder(title: "A")
        let b = makeReminder(title: "B")
        pendingStore(key: key).save([b.calendarItemIdentifier])
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [a, b]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [a, b],
            authorizationStatus: .fullAccess)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A"]) // still hidden
        #expect(pendingStore(key: key).load() == [b.calendarItemIdentifier]) // still incomplete → stays
    }

    @Test
    func reloadDefensivelyDropsCompletedReminder() async {
        let completed = makeReminder(title: "Done")
        completed.isCompleted = true
        let fake = CompletedReturningEventStore(fetchResult: [completed])
        let store = ReminderStore(
            eventStore: fake,
            pendingCompletionStore: pendingStore(key: "pending-\(UUID().uuidString)"),
            loadsReminders: true)

        await store.reload()

        #expect(store.reminders.isEmpty)
    }
}
```

### Verification

#### Automated
- [x] `make test` green with the four new `reload*` cases passing
- [x] Targeted: `xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath DerivedData test -only-testing:SingleThreadTests/ReminderStoreTests`

#### Manual
- [ ] After `reload()`, assert the invariant holds by inspection of the new tests (no UI change at this stage).

---

## Stage 4: Skip refetch — background reconcile

### Changes

#### 1. `applySkipSet` reports success
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

```swift
    @discardableResult
    private func applySkipSet(_ updated: [String], generation: Int? = nil) -> Bool {
        if let generation, generation != skipGeneration {
            return false
        }
        skippedIDs = Set(updated)
        skipStore.save(updated)
        onSkipSetChanged?(updated)
        onRemindersChanged?()
        return true
    }
```

`skipCurrentReminderImmediately()` ignores the return (already `@discardableResult`) — no change.

#### 2. `skipCurrentReminder()` refetches after apply
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

```swift
    public func skipCurrentReminder() {
        guard canMutate else { return }
        guard let reminder = visibleReminders.first else { return }
        let updated = updatedSkipSet(afterSkipping: reminder.calendarItemIdentifier)
        let capturedGeneration = skipGeneration
        Task {
            try? await Task.sleep(nanoseconds: Self.eventKitSettleDelay)
            // Refetch only when the skip actually applied — a clear that raced
            // ahead discards it (generation gate) so no stale refetch runs.
            if applySkipSet(updated, generation: capturedGeneration) {
                await reload()
            }
        }
    }
```

No settle-sleep change; no `canMutate` change. `Task` inherits `@MainActor` from the enclosing method, so `await reload()` is legal.

#### 3. Unit tests
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify (extend the `// MARK: - skipCurrentReminder` section)

```swift
    @Test
    func skipCurrentReminderRefetchesAndDropsCompletedReminder() async {
        let a = makeReminder(title: "A", priority: 1)
        let b = makeReminder(title: "B", priority: 9)
        b.isCompleted = true // "completed on another device"
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [a, b]),
            loadsReminders: true,
            reminders: [a, b],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        store.skipCurrentReminder() // skip A (sorts first)
        try? await Task.sleep(nanoseconds: 400_000_000) // > 200 ms settle + reload

        #expect(store.skippedIDs.contains(a.calendarItemIdentifier))
        #expect(!store.reminders.contains { $0 === b }) // B dropped by refetch
    }

    @Test
    func skipCurrentReminderRefetchKeepsSkippedReminder() async {
        let a = makeReminder(title: "A", priority: 1)
        let b = makeReminder(title: "B", priority: 9)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [a, b]),
            loadsReminders: true,
            reminders: [a, b],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        store.skipCurrentReminder()
        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(store.skippedIDs.contains(a.calendarItemIdentifier))
        #expect(store.reminders.contains { $0 === b }) // incomplete → still fetched
        #expect(store.visibleReminders.map(\.title) == ["B"]) // A hidden by skip only
    }
```

Extend the existing `skipCurrentReminderDiscardedAfterClearSkipped` (currently asserts only `skippedIDs.isEmpty` after the 400 ms wait) with a visibility assertion proving the discarded skip's refetch did not re-apply:

```swift
        // … existing body unchanged through the 400 ms sleep …
        #expect(store.skippedIDs.isEmpty)
        #expect(store.visibleReminders.count == 1) // reminder visible again — skip not re-applied
```

### Verification

#### Automated
- [x] `make test` green; new `skipCurrentReminderRefetches*` cases pass; `skipCurrentReminderDiscardedAfterClearSkipped` still green
- [x] Targeted: `xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath DerivedData test -only-testing:SingleThreadTests/ReminderStoreTests`

#### Manual
- [ ] In the iOS simulator: seed two reminders, complete one on the "other device" (via the Complete swipe), then skip the remaining one — the completed card must not reappear after the skip's background refetch.

---

## Stage 5: Watch completion — pending-set insertion

### Changes

#### 1. Watch `completeReminder` records the pending ID
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

```swift
        #if os(watchOS)
            let removed = reminders.contains { $0.calendarItemIdentifier == identifier }
            reminders.removeAll { $0.calendarItemIdentifier == identifier }
            if removed {
                // Track before the fire-and-forget relay so a reload before the
                // phone processes it cannot resurrect (or double-complete) this
                // reminder. Pruned by `reload()` once the phone catches up.
                pendingCompletions.insert(identifier)
                pendingCompletionStore.save(pendingCompletions)
                onCompleteReminder?(identifier)
            }
            return removed
        #else
```

#### 2. Watch unit tests (new file)
**File**: `SingleThreadWatchTests/ReminderStoreWatchTests.swift`
**Action**: create

The watch branch is live only in the watchOS target. `InMemoryEventStore.makeReminder` is `#if !os(watchOS)`, so use a file-local fixture (same pattern as `ShowCompletionGlowStateTests.swift`):

```swift
import EventKit
import SingleThreadCore
import Testing

@MainActor private let sharedWatchEventStore = EKEventStore()

@MainActor
private func watchReminder(_ title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedWatchEventStore)
    reminder.title = title
    return reminder
}

@MainActor
@Suite(.serialized)
struct ReminderStoreWatchTests {
    private func pendingStore(key: String) -> PendingCompletionStore {
        PendingCompletionStore(defaults: .standard, key: key)
    }

    @Test
    func completeReminderInsertsAndPersistsPendingCompletion() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: false,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        let completed = await store.completeReminder(identifier: rem.calendarItemIdentifier)

        #expect(completed)
        #expect(pendingStore(key: key).load().contains(rem.calendarItemIdentifier))
    }

    @Test
    func reloadHidesPendingCompletion() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let rem = watchReminder("A")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(reminders: [rem]),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: true,
            reminders: [rem],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        _ = await store.completeReminder(identifier: rem.calendarItemIdentifier)
        #expect(pendingStore(key: key).load().contains(rem.calendarItemIdentifier))

        await store.reload() // simulated pull-refresh before phone processes relay

        #expect(store.reminders.isEmpty) // pending-filtered — NOT resurrected
    }

    @Test
    func completeReminderNoOpWhenIdentifierMissing() async {
        let key = "watch-pending-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            pendingCompletionStore: pendingStore(key: key),
            loadsReminders: false,
            reminders: [],
            skippedIDs: [],
            authorizationStatus: .fullAccess)

        let completed = await store.completeReminder(identifier: "nonexistent")

        #expect(!completed)
        #expect(pendingStore(key: key).load().isEmpty)
    }
}
```

#### 3. CI coverage for `SingleThreadWatchTests`
**File**: `scripts/test.sh`
**Action**: modify

Extend the existing "Watch UI tests" block so the build-for-testing also produces `SingleThreadWatchTests`, then add a test-without-building step for it:

```bash
    echo ""
    echo "==> Watch UI tests…"
    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      build-for-testing \
      -only-testing:SingleThreadWatchUITests \
      -only-testing:SingleThreadWatchTests

    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadWatchUITests

    echo ""
    echo "==> Watch unit tests…"
    xcodebuild -scheme "$WATCH_SCHEME" \
      -destination "$WATCH_TEST_SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      test-without-building \
      -only-testing:SingleThreadWatchTests
```

**File**: `.github/workflows/ci.yml`
**Action**: modify

In the `watch-ui-tests` job, add `-only-testing:SingleThreadWatchTests` to the "Build watch app + tests" step's `build-for-testing`, and add a "Watch unit tests" step after "Watch UI tests":

```yaml
      - name: Build watch app + tests
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThreadWatch \
            -destination "platform=watchOS Simulator,id=${{ env.WATCH_UDID }}" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadWatchUITests \
            -only-testing:SingleThreadWatchTests \
            -showBuildTimingSummary

      # … existing "Watch UI tests" step unchanged …

      - name: Watch unit tests
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThreadWatch \
            -destination "platform=watchOS Simulator,id=${{ env.WATCH_UDID }}" \
            -derivedDataPath "$DERIVED_DATA" \
            test-without-building \
            -only-testing:SingleThreadWatchTests
```

No pbxproj or scheme changes — `SingleThreadWatchTests` is already a `TestableReference` in `SingleThreadWatch.xcscheme` (verified).

### Verification

#### Automated
- [x] `make watch-test` green (targeted `-only-testing:SingleThreadWatchTests`)
- [x] `make test` still green (Core package compiles for iOS unchanged)
- [x] CI watch job now executes `SingleThreadWatchTests` (verify via `./scripts/test.sh` full run or `make check`)

#### Manual
- [ ] On a paired watch + phone: complete a reminder on the watch, immediately pull-refresh the watch before the phone processes the relay — the completed reminder must not reappear.

---

## Stage 6: UI/E2E regression guard

### Changes

#### 1. New seeded iOS UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

The `--seed` schema has no `completed` flag, so "pre-complete one in the seed data" is simulated the only way a single app process can: drive the Complete swipe action (the existing `testCompleteViaSwipeRemovesReminder` pattern), which runs the real iOS save → settle → reload round-trip. Seed **three** reminders so the "only the non-completed, non-skipped reminder is visible" assertion is precise.

```swift
    @MainActor
    func testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder() {
        // Three reminders: "CrossDevice" is completed (simulating the other
        // device), "ToSkip" is skipped (triggering the new background refetch),
        // "Remaining" is the only one left visible.
        let seed = #"{"reminders":[{"title":"CrossDevice","priority":1},{"title":"ToSkip","priority":2},{"title":"Remaining","priority":3}]}"#
        let app = launchApp(seedJSON: seed)

        // 1. Complete "CrossDevice" (simulates a cross-device completion).
        XCTAssertTrue(app.staticTexts["CrossDevice"].waitForExistence(timeout: 5))
        app.staticTexts["CrossDevice"].swipeRight()
        let complete = app.buttons["Complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        // 2. Skip "ToSkip" (fires the Stage 4 background refetch).
        XCTAssertTrue(app.staticTexts["ToSkip"].waitForExistence(timeout: 5))
        app.staticTexts["ToSkip"].swipeLeft()
        let skip = app.buttons["Skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()

        // 3. Only the non-completed, non-skipped reminder is visible.
        XCTAssertTrue(
            app.staticTexts["Remaining"].waitForExistence(timeout: 5),
            "The remaining reminder should be the only visible card")
        XCTAssertFalse(app.staticTexts["CrossDevice"].exists, "Completed card must not resurrect")
        XCTAssertFalse(app.staticTexts["ToSkip"].exists, "Skipped card must stay hidden")
    }
```

Existing `testSkipAdvancesToNextReminder`, `testCompleteViaSwipeRemovesReminder`, and the `testUndo…` suite must stay green (unchanged).

### Verification

#### Automated
- [x] `make ui-test` green, including the new `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder`
- [x] Final full gate: `./scripts/test.sh` green end-to-end (format, lint, build, periphery, unit + UI + watch tests)

#### Manual
- [ ] Run the app on iOS: seed two reminders, complete one, skip the other — only the remaining reminder (if any) shows, no completed card reappears after the skip.

---

## Cross-Cutting Notes

- **No transport/API change**: `SkippedReminderSyncService` messages, acks, and dedupe are untouched. The watch relay stays fire-and-forget; correctness comes from the pending set (Stages 1–5).
- **Watch E2E is unit-tested, not UI-tested**: the watch `--ui-testing` seam uses `loadsReminders: false` (no-op `reload()`), so the watch resurrection guard lives in `SingleThreadWatchTests` (Stage 5). Adding a watch `--seed` seam would be a separate change — call it out in the PR rather than silently skipping.
- **No schema/migration layer**: persistence is App Group `UserDefaults`; the new `"pendingCompletionIdentifiers"` key + `PendingCompletionStore` is the closest analog.
- **`pendingCompletionIdentifiers` is deliberately NOT added to `UITestingSeed.persistedKeys`**: the pending set is watch-only; the iOS `--seed` seam never writes it, and watch tests use isolated custom-key `.standard` stores with `defer` cleanup, so no cross-test leakage is possible.
