# Implementation Plan

## Overview

Introduce a `@MainActor public protocol EventKitStoring` that wraps the exact EventKit surface `ReminderStore` calls, conform `EKEventStore` via a public extension, store `any EventKitStoring` inside `ReminderStore`, and prove all five lifecycle paths (`completeReminder`, `addReminder`, `reload`, `start`, `requestAccess`) against a recording `FakeEventStore` — leaving `ReminderStore`'s public API, hooks, sleeps, and `#if os(...)` branches byte-for-byte identical.

---

## Phase 1: Define the seam — protocol + `EKEventStore` conformance

### Changes

#### 1. New seam protocol + conformance
**File**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`
**Action**: create

**Whole file** (auto-discovered by SPM — no Package.swift edits needed):

```swift
import EventKit
import Foundation

/// Test seam: abstracts the EventKit surface `ReminderStore` calls so tests can
/// inject a recording fake. Follows the pattern of `SkipSyncSession` and
/// `SpeechTranscribing`.
@MainActor
public protocol EventKitStoring: AnyObject {
    /// Instance-form authorization check wrapping the `EKEventStore` static.
    func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus

    func requestFullAccessToReminders() async throws -> Bool

    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]?) -> NSPredicate

    @discardableResult
    func fetchReminders(
        matching predicate: NSPredicate,
        completion: @escaping ([EKReminder]?) -> Void) -> Any

    #if !os(watchOS)
        func refreshSourcesIfNecessary()

        func defaultCalendarForNewReminders() -> EKCalendar?

        func save(_ reminder: EKReminder, commit: Bool) throws

        /// Builds a new `EKReminder` from the given fields (was the static
        /// `ReminderStore.makeReminder` factory).
        func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule? = nil) -> EKReminder
    #endif
}

extension EKEventStore: EventKitStoring {
    public func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: entityType)
    }

    #if !os(watchOS)
        public func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule? = nil) -> EKReminder {
            let reminder = EKReminder(eventStore: self)
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = defaultCalendarForNewReminders()
            return reminder
        }
    #endif
}
```

**Key points:**
- The two body-bearing witnesses (`authorizationStatus(for:)`, `makeReminder`) are declared `public` because `EKEventStore` is a public framework type; a private fake (Phase 3) needs no `public` on its witnesses.
- `authorizationStatus(for:)` is an instance requirement wrapping the static — statics can't be instance requirements.
- The always-on set (`authorizationStatus(for:)`, `requestFullAccessToReminders()`, `predicateForIncompleteReminders`, `fetchReminders`) mirrors the unguarded call sites; the rest mirrors the existing `#if !os(watchOS)` split.
- `@discardableResult` on `fetchReminders` is required so the existing call site (which discards its `Any` return) doesn't warn under `SWIFT_TREAT_WARNINGS_AS_ERRORS`.

**Contingency (signature fidelity):** if the compiler reports that a requirement's signature doesn't match EventKit's imported signature (e.g. `fetchReminders` return type or `requestFullAccessToReminders` async form), copy the exact imported signature from the fix-it diagnostic — the body-bearing approach in Decision 4 extends to any requirement. No behavioral impact.

### Verification

#### Automated
- [x] `make build` passes (iOS — protocol + conformance compile)
- [x] `make watch-build` passes (**proves `#if !os(watchOS)` gating is correct**)
- [x] `make mac-build` passes (macOS — `save`/`makeReminder`/`refreshSourcesIfNecessary`/`defaultCalendarForNewReminders` requirements present)

#### Manual
- [x] No "does not conform to protocol 'EventKitStoring'" diagnostics in any of the three builds.
- [x] `ReminderStore.swift` is byte-for-byte untouched in this phase (git diff shows only the new file).

---

## Phase 2: `ReminderStore` consumes the seam

### Changes

#### 1. Storage, init default, and call sites
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

**(a)** Field + production-injection type (line 13 & `private let eventStore`):

```swift
public init(
    eventStore: any EventKitStoring = EKEventStore(),
    skipStore: SkippedReminderStore = SkippedReminderStore(),
    loadsReminders: Bool = true) {
```

```swift
private let eventStore: any EventKitStoring
```

**(b)** `start()` — replace the static read (line 69):

```swift
let current = eventStore.authorizationStatus(for: .reminder)
```

**(c)** `addReminder` — replace `Self.makeReminder(...)` (lines 118–123):

```swift
let reminder = eventStore.makeReminder(
    title: title,
    notes: notes,
    dueDate: dueDate,
    recurrenceRule: recurrenceRule)
```

**(d)** `requestAccess()` — drop `private` (becomes `internal`, extracted for testability), and replace both static reads (lines 221, 224):

```swift
func requestAccess() async {
    do {
        let granted = try await eventStore.requestFullAccessToReminders()
        if granted {
            authorizationStatus = .fullAccess
            await reload()
        } else {
            authorizationStatus = eventStore.authorizationStatus(for: .reminder)
        }
    } catch {
        authorizationStatus = eventStore.authorizationStatus(for: .reminder)
    }
}
```

**(e)** Delete the entire static factory block (lines ~177–196), i.e.:

```swift
    // MARK: Internal

    #if !os(watchOS)
        /// Builds a new `EKReminder` from the given fields. Extracted for testability.
        static func makeReminder(...) -> EKReminder { ... }
    #endif
```

**Unchanged on purpose:** the preview/test init's `eventStore = EKEventStore()` (implicit conversion to `any EventKitStoring` still works), the three hooks, the 200 ms sleeps, `fetchReminders(matching:)` async bridge, and every `#if os(...)` branch.

#### 2. Rewrite `MakeReminderTests` to target the conformance body
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify (the six `@Test`s inside `#if !os(watchOS)` `struct MakeReminderTests`; delete `ReminderStore.makeReminder` and its `eventStore:` argument)

The six assertions stay identical; only the call site changes. New call shape:

```swift
let reminder = (EKEventStore() as any EventKitStoring).makeReminder(
    title: "Buy milk",
    notes: nil,
    dueDate: nil)
```

Per-test mapping (all inside the existing `#if !os(watchOS)`):

- `makeReminderSetsTitle`: `title: "Buy milk"`; assert `reminder.title == "Buy milk"`.
- `makeReminderSetsNotes`: `notes: "Two percent"`; assert `reminder.notes == "Two percent"`.
- `makeReminderSetsDueDate`: pass `dueDate`; assert `year/month/day`.
- `makeReminderLeavesUnsetFieldsNil`: no extra args; assert `notes == nil`, `dueDateComponents == nil`, `hasRecurrenceRules == false`.
- `makeReminderSetsRecurrenceRule`: pass `recurrenceRule: rule`; assert `recurrenceRules?.count == 1`, frequency `.weekly`, interval 1.
- `makeReminderSetsDefaultCalendar`:

```swift
let eventStore = EKEventStore()
let reminder = (eventStore as any EventKitStoring).makeReminder(
    title: "Buy milk",
    notes: nil,
    dueDate: nil)
#expect(reminder.calendar == eventStore.defaultCalendarForNewReminders())
```

### Verification

#### Automated
- [x] `make test` passes — all pre-existing suites + rewritten `MakeReminderTests` green (this is the byte-for-byte-equivalence proof).
- [x] `make mac-test` passes (macOS unit suite; `MakeReminderTests` and write paths compile and run unguarded on macOS).

#### Manual
- [x] `grep -n "EKEventStore.authorizationStatus" SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` returns nothing (all static reads now go through `eventStore`).
- [x] `grep -n "makeReminder\|Self.makeReminder" SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` returns only the `eventStore.makeReminder(...)` call inside `addReminder`.
- [x] `git diff` of `ReminderStore.swift` shows no changes to public API, hooks, sleeps, or `#if os(...)` branches beyond the listed edits.

---

## Phase 3: Write-path tests — `FakeEventStore` + save/makeReminder coverage

### Changes

#### 1. Recording fake + write suites
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: create

```swift
import EventKit
import Foundation
@testable import SingleThreadCore
import Testing

// MARK: - Recording fake

@MainActor
private final class FakeEventStore: EventKitStoring {
    // MARK: Lifecycle

    init(
        authStatus: EKAuthorizationStatus = .notDetermined,
        accessGranted: Bool = true,
        accessError: (any Error)? = nil,
        fetchResult: [EKReminder] = [],
        defaultCalendar: EKCalendar? = nil) {
        self.authStatus = authStatus
        self.accessGranted = accessGranted
        self.accessError = accessError
        self.fetchResult = fetchResult
        self.defaultCalendar = defaultCalendar
    }

    // MARK: Configuration

    var authStatus: EKAuthorizationStatus
    var accessGranted: Bool
    var accessError: (any Error)?
    var fetchResult: [EKReminder]
    var defaultCalendar: EKCalendar?
    var saveShouldThrow = false

    // MARK: Recording

    private(set) var saved: [EKReminder] = []
    private(set) var lastSaveCommit: Bool?
    private(set) var lastPredicate: NSPredicate?
    private(set) var fetchCallCount = 0
    private(set) var requestAccessCallCount = 0
    private(set) var refreshCallCount = 0

    // MARK: EventKitStoring

    func authorizationStatus(for _: EKEntityType) -> EKAuthorizationStatus {
        authStatus
    }

    func requestFullAccessToReminders() async throws -> Bool {
        requestAccessCallCount += 1
        if let accessError {
            throw accessError
        }
        return accessGranted
    }

    func predicateForIncompleteReminders(
        withDueDateStarting _: Date?,
        ending _: Date?,
        calendars _: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
    }

    @discardableResult
    func fetchReminders(
        matching predicate: NSPredicate,
        completion: @escaping ([EKReminder]?) -> Void) -> Any {
        fetchCallCount += 1
        lastPredicate = predicate
        completion(fetchResult)
        return ()
    }

    #if !os(watchOS)
        func refreshSourcesIfNecessary() {
            refreshCallCount += 1
        }

        func defaultCalendarForNewReminders() -> EKCalendar? {
            defaultCalendar
        }

        func save(_ reminder: EKReminder, commit: Bool) throws {
            lastSaveCommit = commit
            if saveShouldThrow {
                throw NSError(domain: "FakeEventStore", code: 1)
            }
            saved.append(reminder)
        }

        func makeReminder(
            title: String,
            notes: String?,
            dueDate: DateComponents?,
            recurrenceRule: EKRecurrenceRule?) -> EKReminder {
            let reminder = EKReminder(eventStore: EKEventStore())
            reminder.title = title
            reminder.notes = notes
            reminder.dueDateComponents = dueDate
            if let recurrenceRule {
                reminder.addRecurrenceRule(recurrenceRule)
            }
            reminder.calendar = defaultCalendar
            return reminder
        }
    #endif
}

// MARK: - Write-path tests

#if !os(watchOS)
    @MainActor
    @Suite(.serialized)
    struct ReminderStoreWriteTests {
        @Test
        func completeReminderMarksSavedAndReloads() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.completeReminder(identifier: reminder.calendarItemIdentifier)

            #expect(reminder.isCompleted)
            #expect(fake.saved.count == 1)
            #expect(fake.saved.first === reminder)
            #expect(fake.lastSaveCommit == true)
            #expect(fake.lastPredicate != nil)
            #expect(fake.fetchCallCount == before + 1) // reload-after-save
        }

        @Test
        func completeReminderSaveErrorStaysSilentAndSkipsReload() async {
            let reminder = makeReminder(title: "Task")
            let fake = FakeEventStore(fetchResult: [reminder])
            fake.saveShouldThrow = true
            let store = testStore(eventStore: fake)
            await store.reload()
            let before = fake.fetchCallCount

            await store.completeReminder(identifier: reminder.calendarItemIdentifier)

            #expect(fake.saved.isEmpty)
            #expect(fake.fetchCallCount == before) // no reload on save error
        }

        @Test
        func addReminderSavesAndReturnsTrue() async {
            let fake = FakeEventStore()
            let store = testStore(eventStore: fake)
            let dueDate = DateComponents(year: 2026, month: 1, day: 2)
            let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)

            let savedResult = await store.addReminder(
                title: "New",
                notes: "Note",
                dueDate: dueDate,
                recurrenceRule: rule)

            #expect(savedResult)
            #expect(fake.saved.count == 1)
            #expect(fake.saved.first?.title == "New")
            #expect(fake.saved.first?.notes == "Note")
            #expect(fake.saved.first?.dueDateComponents?.day == 2)
            #expect(fake.saved.first?.recurrenceRules?.count == 1)
            #expect(fake.lastSaveCommit == true)
            #expect(fake.lastPredicate != nil) // reload-after-save re-fetched
        }

        @Test
        func addReminderSaveErrorReturnsFalse() async {
            let fake = FakeEventStore()
            fake.saveShouldThrow = true
            let store = testStore(eventStore: fake)

            let savedResult = await store.addReminder(title: "New", notes: nil, dueDate: nil)

            #expect(!savedResult)
            #expect(fake.saved.isEmpty)
        }
    }
#endif

// MARK: - Fixtures

private func makeReminder(title: String) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.title = title
    return reminder
}

private func testStore(eventStore: any EventKitStoring) -> ReminderStore {
    let skipStore = SkippedReminderStore(
        defaults: .standard,
        key: "test-\(UUID().uuidString)")
    return ReminderStore(eventStore: eventStore, skipStore: skipStore, loadsReminders: true)
}
```

**Key points:**
- The fake records `saved` (reminders passed to `save`), `lastSaveCommit`, `lastPredicate`, and call counts. `makeReminder` reuses a real inert `EKReminder(eventStore: EKEventStore())` and applies `defaultCalendar`.
- `completeReminder` writes `isCompleted = true` **before** `save`, so on save-error the flag is still set on the reference — assert `saved.isEmpty` (not `isCompleted == false`).
- `addReminder`'s reload-after-save re-fetches, so `lastPredicate` is non-nil and `saved.first` carries the built reminder's fields.
- Inject a UUID-keyed `SkippedReminderStore` so `reload()`'s skip-resolution never sees stale `UserDefaults` state; `loadsReminders: true` lets `reload()` actually run.
- The write suites mirror the production `#if !os(watchOS)` write-path guard, exactly like `MakeReminderTests` does today.

### Verification

#### Automated
- [x] `make test` passes — new write suites green, existing suites still green (no regression).

#### Manual
- [x] Confirm `fake.saved` contents are asserted (title/notes/dueDate/recurrenceRule) and `fake.lastPredicate != nil` in the `addReminder` success test.
- [x] Confirm the save-error tests assert `fake.saved.isEmpty` and no extra reload (`fetchCallCount` unchanged).

---

## Phase 4: Read/lifecycle tests — `reload`, `start`, `requestAccess`

### Changes

#### 1. Extend `EventKitStoringTests.swift` with lifecycle suites
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify (append; `FakeEventStore` needs no structural change)

Add below the write suites (shares the `makeReminder`/`testStore` fixtures; not platform-guarded because the read path compiles on all three platforms):

```swift
// MARK: - Lifecycle tests

@MainActor
@Suite(.serialized)
struct ReminderStoreLifecycleTests {
    @Test
    func reloadPopulatesRemindersFromFetch() async {
        let first = makeReminder(title: "A")
        let second = makeReminder(title: "B")
        let fake = FakeEventStore(fetchResult: [first, second])
        let store = testStore(eventStore: fake)

        await store.reload()

        #expect(store.reminders.map(\.title) == ["A", "B"])
        #expect(fake.fetchCallCount == 1)
        #expect(fake.lastPredicate != nil)
        #if !os(watchOS)
            #expect(fake.refreshCallCount == 1)
        #endif
    }

    @Test
    func startWithFullAccessFetchesWithoutRequesting() async {
        let fake = FakeEventStore(
            authStatus: .fullAccess,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.start()

        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 1)
        #expect(fake.requestAccessCallCount == 0)
    }

    @Test
    func startWithoutAccessRequestsThenReloads() async {
        let fake = FakeEventStore(
            authStatus: .notDetermined,
            accessGranted: true,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.start()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 1)
    }

    @Test
    func requestAccessGrantSetsFullAccessAndReloads() async {
        let fake = FakeEventStore(
            authStatus: .notDetermined,
            accessGranted: true,
            fetchResult: [makeReminder(title: "A")])
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .fullAccess)
        #expect(fake.fetchCallCount == 1)
    }

    @Test
    func requestAccessDenyRereadsStatusWithoutFetching() async {
        let fake = FakeEventStore(authStatus: .denied, accessGranted: false)
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .denied)
        #expect(fake.fetchCallCount == 0)
    }

    @Test
    func requestAccessErrorRereadsStatusWithoutFetching() async {
        let fake = FakeEventStore(
            authStatus: .restricted,
            accessError: NSError(domain: "test", code: 1))
        let store = testStore(eventStore: fake)

        await store.requestAccess()

        #expect(fake.requestAccessCallCount == 1)
        #expect(store.authorizationStatus == .restricted)
        #expect(fake.fetchCallCount == 0)
    }

    @Test
    func loadsRemindersFalseMakesReadPathsNoOps() async {
        let fake = FakeEventStore(
            authStatus: .fullAccess,
            fetchResult: [makeReminder(title: "A")])
        let skipStore = SkippedReminderStore(
            defaults: .standard,
            key: "test-\(UUID().uuidString)")
        let store = ReminderStore(
            eventStore: fake,
            skipStore: skipStore,
            loadsReminders: false)

        await store.start()
        await store.reload()

        #expect(fake.fetchCallCount == 0)
        #expect(fake.requestAccessCallCount == 0)
        #expect(store.reminders.isEmpty)
    }
}
```

**Key points / correctness notes:**
- `requestAccess` (now `internal`) is called directly via `@testable import`; the three branches (grant/deny/throw) map one-to-one to the method's body.
- Deny and error both re-read `eventStore.authorizationStatus(for: .reminder)` and end at `fake.authStatus` without fetching.
- **`loadsReminders == false` nuance:** only `start()` and `reload()` carry the guard. `requestAccess()` itself has *no* `loadsReminders` guard (it only indirectly no-ops via its `reload()` call). The no-op test therefore exercises `start()` + `reload()` only, asserting fetch/request counts are 0 — do **not** call `requestAccess()` in that test.

### Verification

#### Automated
- [x] `make test` passes — lifecycle suites green; fake's `fetchCallCount`/`requestAccessCallCount` and `authorizationStatus` transitions match each branch.
- [x] `./scripts/test.sh` passes (final gate: format · SwiftFormat check · SwiftLint `--strict` · iOS build · watch build · **Periphery** · unit tests · UI tests · macOS build · macOS unit tests).

#### Manual
- [x] Periphery (`make periphery` / `scripts/test.sh`) reports no new unused declarations — the deleted static `makeReminder` is gone and every protocol requirement is exercised (the protocol surface and `FakeEventStore` are referenced from test code / `ReminderStore`).
- [x] `make format && make lint` clean before committing.

---

## Testing Checkpoints

- **After Phase 1**: protocol + conformance compile on iOS, watchOS, macOS. `ReminderStore` untouched — zero behavior risk; safe resume point.
- **After Phase 2**: seam fully wired; `ReminderStore` behavior byte-for-byte identical. All pre-existing tests green is the proof.
- **After Phase 3**: write paths proven through the recording fake (saves, reload-after-save, predicate reuse).
- **After Phase 4**: all five lifecycle paths covered. Final gate `./scripts/test.sh` (Periphery must not flag the now-deleted static `makeReminder` or an unused protocol surface).

---

## Deviations from Plan (recorded during implementation)

1. **Phase 1 — removed default argument from protocol requirement.**
   Swift does not permit default argument values in protocol method declarations
   (`recurrenceRule: EKRecurrenceRule? = nil` → compile error). The default was
   removed from the requirement (the conformance witness keeps `= nil`; `ReminderStore.addReminder`
   and the tests pass the argument explicitly).

2. **Phase 4 — removed `defaultCalendarForNewReminders()` from the protocol.**
   Periphery (`--strict`, `retain_public: false`) flags it as unused: after `makeReminder`
   moved *into* the seam, no code dispatches `defaultCalendarForNewReminders()` through
   `any EventKitStoring` — the `EKEventStore` conformance body calls it via `self` (concrete),
   and the plan's own `FakeEventStore.makeReminder` uses the `defaultCalendar` property directly.
   The redundant requirement was removed from the protocol and the fake; the `makeReminder`
   conformance body still assigns the calendar via the concrete `EKEventStore` method.

3. **Phase 3 — `FakeEventStore.lastSaveCommit` is a non-optional `Bool` (default `false`).**
   SwiftLint's opt-in `discouraged_optional_boolean` forbids `Bool?`. Tests only assert
   `== true` after a successful save, so a `false` default is equivalent.

4. **`testStore` fixture is `@MainActor`.** The `SingleThreadTests` target does *not* inherit
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (set only on the app target), so the free
   fixture function constructing `ReminderStore` must be explicitly `@MainActor`.

5. **macOS builds/tests need `CODE_SIGNING_ALLOWED=NO`** on this machine (no provisioning
   profile). The `make mac-build`/`make mac-test` targets omit it; the CI-equivalent commands
   in `scripts/test.sh` pass it and succeed.