# Design Discussion

## Current State

`ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:4-6`) is the
app's sole owner of an `EKEventStore` (`ReminderStore.swift:200`). Every EventKit call
funnels through it, so it can only be unit-tested on the pure-logic paths
(`visibleReminders`, `skipCurrentReminder`, and the static `makeReminder` factory). Its
save, fetch, reload, and access-request paths reach real EventKit regardless of how the
store was constructed:

- `start()` reads the static `EKEventStore.authorizationStatus(for: .reminder)`
  (`:69`) then either `reload()`s or `requestAccess()`es.
- `requestAccess()` calls `requestFullAccessToReminders()` and re-reads the static status
  (`:216,221,224`).
- `reload()` calls `refreshSourcesIfNecessary()` (`:155`, non-watchOS), builds a
  predicate (`:157-160`), and bridges the completion-handler `fetchReminders` to
  async/await in a private helper (`:206-212`).
- `completeReminder` sets `isCompleted = true` then `eventStore.save` (`:90-91`);
  `addReminder` builds via the static `makeReminder` factory then `save` (`:118-125`).
- `EKReminder(eventStore:)` requires a concrete `EKEventStore` (`:186`), which the
  factory receives from `private let eventStore` (`:193`).

The existing test seam is constructor injection (`eventStore:` default arg, `:13`) plus a
pre-populated-state initializer (`:22-33`) that constructs an inert real `EKEventStore()`
(`:31`). Tests like `addReminderDoesNotCrashWithoutAccess` only assert "no crash"
(`ReminderStoreTests.swift:83-93`) because the save path is not mockable.

WatchConnectivity and Speech are already abstracted behind small `AnyObject` protocol
seams (`SkipSyncSession` at `SkippedReminderSyncService.swift:7-16`; `SpeechTranscribing` at
`ReminderDictation.swift:9-16`). EventKit is the notable exception.

## Desired End State

A `@MainActor` public protocol — `EventKitStoring` — wrapping exactly the EventKit
surface `ReminderStore` calls, placed in a new file
`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift` (auto-discovered by SPM).

`ReminderStore` stores `private let eventStore: any EventKitStoring` and otherwise keeps
its public API, `#if os(...)` branches, hooks, 200 ms sleeps, and reload-after-save
behavior byte-for-byte identical. `EKEventStore` gains an empty conformance (plus minimal
bodies for the methods EventKit doesn't expose with matching signatures).

Verification: five new `@MainActor` test suites (or one suite) in
`SingleThreadTests` exercising `completeReminder`, `addReminder`, `reload`, `start`, and
`requestAccess` against a recording `FakeEventStore` — asserting saves, predicate reuse,
fetch results, auth-status transitions, and reload re-fetch. All existing tests stay
green; full pipeline via `./scripts/test.sh`.

## Patterns to Follow

- **Seam shape** — small `AnyObject` protocol exposing only the called subset; existential
  (`any`) storage; production passes the real type, tests pass a recording fake
  (`SkipSyncSession` `SkippedReminderSyncService.swift:7-16,100`; `SpeechTranscribing`
  `ReminderDictation.swift:9-16`). Followed for `EventKitStoring`.
- **Empty conformance on the framework type** — `extension WCSession: SkipSyncSession {}`
  (`SkippedReminderSyncService.swift:16`). Followed for `extension EKEventStore:
  EventKitStoring`, except EventKit needs two body-bearing requirements (see Decisions 3, 4).
- **`@MainActor` on the seam** — `SpeechTranscribing` is `@MainActor`
  (`ReminderDictation.swift:11`), matching `ReminderStore`'s isolation. Followed; the EventKit
  fake is also `@MainActor`.
- **Recording fake + `@Suite(.serialized)` + `@MainActor`** — `FakeSession`
  (`SkippedReminderSyncServiceTests.swift:8-31`), suites in `ReminderStoreTests.swift:5-7`,
  injected per-test. Followed for `FakeEventStore`.
- **Test of an internal/factory seam under `#if !os(...)`** — `MakeReminderTests`
  (`ReminderStoreTests.swift:246-316`) guards on `#if !os(watchOS)` mirroring the production
  guard; single-shape fixtures built from `EKReminder(eventStore: EKEventStore())`
  (`:321-327`). Followed; new write-path tests reuse the `#if !os(...)` mirror.
- **`@retroactive @unchecked Sendable` on `EKReminder`** — remains required for `EKReminder`
  to cross async boundaries (`ReminderDateFilter.swift:4`). The protocol keeps `EKReminder`
  as a passthrough type; no change.

**Do NOT follow**: `SpeechTranscribing`'s app-owned wrapper conformer (a real class
implementing the protocol, `ReminderDictation.swift:24`). `EKEventStore` already exists and
its methods largely match, so a wrapper would be dead boilerplate. Also do NOT follow the
preview/test init's "never touches EventKit" doc-claim-but-not-body problem
(`ReminderStore.swift:21` vs `:31`) — keep the doc honest about the inert construction.

## Design Decisions

1. **Single `EventKitStoring` protocol (no read/write split)**: one protocol wrapping the
   full surface. Matches the `SkipSyncSession`/`SpeechTranscribing` precedent; watchOS's
   read-only split is already expressed by `#if os(watchOS)` in `ReminderStore.swift:84-133`,
   so a protocol split would duplicate it.

2. **Reminder construction moves into the protocol**: protocol gains
   `func makeReminder(title:notes:dueDate:recurrenceRule:) -> EKReminder`. The real conformer
   does `EKReminder(eventStore: self)` plus the four field assignments + calendar
   (`ReminderStore.swift:186-193`). The `static makeReminder` factory is deleted; its
   `MakeReminderTests` move to assert the conformance body instead. The fake returns a
   hand-built `EKReminder(eventStore: EKEventStore())`. Rationale: a `any` existential can't
   feed `EKReminder(eventStore:)`, so construction must live on the other side of the seam.

3. **Faithful completion-handler `fetchReminders`**: protocol mirrors
   `fetchReminders(matching:completion:)` exactly, so the conformance is empty for this
   requirement and the async bridge stays private in `ReminderStore` (`:206-212`). Matches
   the empty-conformance idiom of `SkipSyncSession`; avoids a body-bearing bridge like
   `SpeechTranscribing.transcribe`.

4. **Instance `authorizationStatus(for:)` on the protocol**: the static
   `EKEventStore.authorizationStatus(for:)` (`:69,221,224`) becomes an instance requirement
   `func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus`, with a
   one-line body delegating to the static. Statics can't be instance requirements; this keeps
   `start`/`requestAccess` fully faked while `EKEventStore` stays the only place that touches
   the real static.

5. **Public `extension EKEventStore: EventKitStoring` in `SingleThreadCore`** (SkipSyncSession
   shape, not the wrapper shape), marked `@MainActor`. Protocol and conformance are both
   `public` because `ReminderStore` is `public`. Naming: `EventKitStoring` (gerund idiom,
   parallel to `SpeechTranscribing`).

6. **`#if !os(watchOS)` gating inside the protocol**: `save(_:commit:)`,
   `refreshSourcesIfNecessary()`, `defaultCalendarForNewReminders()`, and `makeReminder` are
   `__WATCHOS_PROHIBITED` or only-used-off-watchOS, so those requirements (and the
   corresponding conformance bodies) sit behind `#if !os(watchOS)`. The always-available set —
   `authorizationStatus(for:)`, `requestFullAccessToReminders()`, `predicateForIncompleteReminders`,
   `fetchReminders(matching:completion:)` — compiles on all three platforms (mirrors the
   existing split in `ReminderStore.swift:154-156,178-196`).

7. **`requestAccess()` becomes `internal`**: currently `private` (`:214`); to unit-test it
   directly (the task requires it), raise it to `internal` — the same "extracted for
   testability" move already applied to `makeReminder` (`ReminderStore.swift:177`).

## What We're NOT Doing

- NOT changing `ReminderStore`'s public API surface, its three initializers, the
  `loadsReminders` guard (`:68,153`), the three hooks, the 200 ms sleeps (`:92,126,144`), or
  reload-after-save.
- NOT abstracting `EKReminder`, `EKRecurrenceRule`, `NSPredicate`, or `EKCalendar` — they
  pass through the protocol as value/parameter types, exactly as `SkipSyncSession` passes
  `[String: Any]`.
- NOT touching the watchOS read-only behavior or any `#if os(...)` branch; the abstracted
  calls still respect them.
- NOT refactoring `SkippedReminderStore`, WatchConnectivity sync, the widget, or App Intents;
  the widget's own static auth check (`NextThingWidget.swift:52`) and its separate store
  instance stay untouched.
- NOT sharing a single store across app/watch/widget — each layer keeps constructing its own
  (`SingleThreadApp.swift:17`, `SingleThreadWatchApp.swift:10`, `NextThingWidget.swift:54`).
- NOT making the protocol `Sendable`/off-main-actor; it stays `@MainActor` like
  `SpeechTranscribing`.
- NOT renaming or moving the `skipCurrentReminder` path, which already works without EventKit
  (`ReminderStore.swift:136-150`).

## Open Risks

- **`MakeReminderTests` churn**: deleting the static `makeReminder` factory (Decision 2)
  forces rewriting `MakeReminderTests` (`ReminderStoreTests.swift:246-316`) to target the
  conformance body. Field-nil and default-calendar assertions need a real `EKEventStore` for
  `defaultCalendarForNewReminders` pass-through — construction remains inert, so this should
  hold without entitlements.
- **`defaultCalendarForNewReminders` on the fake**: a `FakeEventStore` must return a calendar
  for `makeReminder`'s `reminder.calendar` assignment. If `nil` is returned, real EventKit
  tolerates it, but the design should pin the fake's return and assert accordingly.
- **`requestFullAccessToReminders()` async import**: relies on the Swift async importer (iOS
  17/vendor 10 signature). If the async form differs across platforms, the requirement may
  need an explicit bridge like Decision 4's. Low risk — `ReminderStore.swift:216` already
  calls it directly.
- **`fetchReminders` signature fidelity**: the completion-handler returns an ObjC `id`
  (ignored `Any` in Swift). The requirement declares the `@discardableResult` shape; if the
  exact imported signature doesn't satisfy the requirement, a tiny conformance body bridges
  it — acceptable, deviates from the "empty conformance" claim slightly.
- **Exact conformance matching**: Swift requires the conformance extension's method labels
  to match EventKit's imported names (`predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)`,
  `save(_:commit:)`). Any label mismatch surfaces at compile time and is a mechanical fix;
  the design's method list is drawn straight from `ReminderStore.swift`'s existing call
  sites, minimizing surprise.