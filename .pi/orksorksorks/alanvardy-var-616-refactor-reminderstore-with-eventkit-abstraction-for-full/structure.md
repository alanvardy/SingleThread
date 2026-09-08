# Structure Outline

## Approach

Extract the EventKit surface `ReminderStore` calls into a `@MainActor` `EventKitStoring`
protocol, conform `EKEventStore` via a public conformance extension, store
`any EventKitStoring` inside `ReminderStore`, and prove all five lifecycle paths
(`completeReminder`, `addReminder`, `reload`, `start`, `requestAccess`) against a
recording `FakeEventStore` — keeping `ReminderStore`'s public API, hooks, sleeps, and
`#if os(...)` branches byte-for-byte identical.

**Slicing note**: this is a single-module seam refactor (no DB/API/UI layers). The
"layers" are **protocol → framework conformance → consumer → test target**. Phase 2 is
intentionally one atomic compile boundary: `eventStore` can't become `any EventKitStoring`
until every call site is covered by the protocol *and* the static `makeReminder` factory is
deleted (an `any` existential can't be passed to `EKReminder(eventStore:)`).

---

## Phase 1: Define the seam — protocol + `EKEventStore` conformance

Introduce the `EventKitStoring` type and its conformance on `EKEventStore`, **without
touching `ReminderStore`** (the static `makeReminder` factory temporarily coexists). This
proves the seam compiles and behaves on its own.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift` (new)

**Key changes**:
- `@MainActor public protocol EventKitStoring: AnyObject` — new
  - `func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus`
  - `func requestFullAccessToReminders() async throws -> Bool`
  - `func predicateForIncompleteReminders(withDueDateStarting: Date?, ending: Date?, calendars: [EKCalendar]?) -> NSPredicate`
  - `@discardableResult func fetchReminders(matching predicate: NSPredicate, completion: @escaping ([EKReminder]?) -> Void) -> Any`
  - `#if !os(watchOS)` only: `refreshSourcesIfNecessary()`, `defaultCalendarForNewReminders() -> EKCalendar?`, `save(_ reminder: EKReminder, commit: Bool) throws`, `makeReminder(title: String, notes: String?, dueDate: DateComponents?, recurrenceRule: EKRecurrenceRule?) -> EKReminder`
- `extension EKEventStore: EventKitStoring { }` — new (mostly empty conformance)
  - body-bearing: `authorizationStatus(for:)` delegates to the static
    `EKEventStore.authorizationStatus(for:)`; `makeReminder` holds the
    `EKReminder(eventStore: self)` + field-assignment + `calendar` logic

**Verify**: `make build && make watch-build && make mac-build` (protocol + conformance must
satisfy on all three platforms — the watchOS build is what proves the `#if !os(watchOS)`
gating is correct). Manual: no "cannot conform" / "does not conform" diagnostics.

---

## Phase 2: `ReminderStore` consumes the seam

Swap storage to the existential, drive every EventKit call through the protocol, delete the
static factory, and expose `requestAccess` for testing. Public API and all
sleeps/hooks/guards stay identical.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
- `private let eventStore: any EventKitStoring` — was `private let eventStore: EKEventStore`
- `init(eventStore: any EventKitStoring = EKEventStore(), skipStore: SkippedReminderStore = …, loadsReminders: Bool = true)` — default arg unchanged in behavior
- `start()` → `let current = eventStore.authorizationStatus(for: .reminder)` — replace static read
- `requestAccess()` → `internal` (was `private`); both deny/error paths use `eventStore.authorizationStatus(for: .reminder)`
- `addReminder` → `let reminder = eventStore.makeReminder(title:notes:dueDate:recurrenceRule:)` — no `Self.`, no `eventStore:` arg
- **delete** `static func makeReminder(...)` — factory moves inside the conformance (Phase 1)
- `MakeReminderTests` → rewritten to call `(EKEventStore() as any EventKitStoring).makeReminder(...)`; six assertions unchanged
- preview/test init `eventStore = EKEventStore()` — unchanged (`EKEventStore` still conforms)

**Verify**: `make test` passes (all existing suites + rewritten `MakeReminderTests` green);
`make mac-test` passes. Manual: `ReminderStore.swift` no longer references
`EKEventStore.authorizationStatus` statically.

---

## Phase 3: Write-path tests — `FakeEventStore` + save/makeReminder coverage

Add a recording fake and prove the two mutation paths exercise saves, reload-after-save,
and reminder construction through the seam.

**Files**: `SingleThreadTests/EventKitStoringTests.swift` (new; `FakeEventStore` + write
suites)

**Key changes**:
- `@MainActor final class FakeEventStore: EventKitStoring` — new
  - config: `authStatus: EKAuthorizationStatus`, `accessResult: Bool` (or throw), `fetchResult: [EKReminder]`, `defaultCalendar: EKCalendar?`
  - recording: `private(set) var saved: [EKReminder]`, `private(set) var lastPredicate: NSPredicate?`, `fetchCallCount: Int`
  - `makeReminder` reuses `EKReminder(eventStore: EKEventStore())` + `defaultCalendar`
- new `@Suite(.serialized) struct ReminderStoreWriteTests`:
  - `completeReminder(identifier:)` → `isCompleted == true` on saved reminder; `reload()` re-fetches
  - `addReminder(...)` → `save(_:commit: true)` recorded; returns `true`; `lastPredicate` reused on reload
  - save-error paths → `completeReminder` stays silent, `addReminder` returns `false` (mirror `#if !os(macOS)` guard as today)

**Verify**: `make test` — new write suites pass. Manual: assert `fake.saved` contents and
`fake.lastPredicate` non-nil; existing tests still green (no behavior regression).

---

## Phase 4: Read/lifecycle tests — `reload`, `start`, `requestAccess`

Complete the coverage of the design's five paths by exercising the fetch/predicate,
auth-status transitions, and access-request branching against the fake.

**Files**: `SingleThreadTests/EventKitStoringTests.swift` (extend fake + add lifecycle suites)

**Key changes**:
- `FakeEventStore` gains nothing structural (existing config/recording is sufficient)
- new `@Suite(.serialized) struct ReminderStoreLifecycleTests`:
  - `reload()` → sets `reminders = fetchResult`; predicate built from `overdueCutoff()`/`endOfToday()`; skip-set resolved
  - `start()` → `.fullAccess` ⇒ fetch happens, no request; otherwise `requestFullAccessToReminders()` called
  - `requestAccess()` → grant ⇒ `.fullAccess` + fetch; deny ⇒ status = `fake.authStatus`; throw ⇒ status = `fake.authStatus`
  - `loadsReminders == false` ⇒ every path is a no-op (fetch count 0)

**Verify**: `make test` — lifecycle suites pass. Manual: fake's `fetchCallCount` matches the
expected count per branch; `authorizationStatus` transitions match the fake's staged status.

---

## Testing Checkpoints

- **After Phase 1**: protocol + conformance compile on iOS, watchOS, macOS. `ReminderStore`
  is untouched — zero behavior risk. Safe resume point.
- **After Phase 2**: seam fully wired; `ReminderStore` behavior is byte-for-byte identical
  (same public API/sleeps/hooks). All pre-existing tests green is the proof.
- **After Phase 3**: write paths proven through the recording fake (saves, reload-after-save,
  predicate reuse).
- **After Phase 4**: all five lifecycle paths covered. Final gate: `./scripts/test.sh`
  (format · lint · Periphery · unit · UI) — Periphery must not flag the now-unused static
  `makeReminder` (deleted in Phase 2) or the protocol surface.