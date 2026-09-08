# Research Questions

## Context

Focus on the `SingleThreadCore` Swift package and the iOS app target. In
particular, trace how `ReminderStore` uses EventKit (`EKEventStore`,
`EKReminder`, predicates, authorization) across its lifecycle, how it is
constructed and wired by the app entry points, which platform-specific
`#if os(...)` branches change its behavior, what existing protocol-based test
seams the codebase uses for non-mockable Apple frameworks, and how its unit
tests are structured and run.

## Questions

1. What is the full inventory of EventKit API surface that `ReminderStore`
   touches directly — `EKEventStore` methods (authorization status, refresh,
   predicate construction, fetch with completion handler, save, full-access
   request, default calendar), static `EKEventStore.authorizationStatus(for:)`,
   and `EKReminder(eventStore:)` — and at which point in the store lifecycle
   (`start`, `reload`, `addReminder`, `completeReminder`, `requestAccess`) does
   each call occur?

2. How does `ReminderStore` expose testability today? Trace its two
   initializers (production vs. preview/test), the `loadsReminders` flag, and
   how existing tests and previews construct instances; identify which public
   methods' bodies still reach real EventKit regardless of how the store was
   constructed.

3. What protocol-based "test seam" precedents already exist in the codebase for
   non-mockable system frameworks? Trace `SkipSyncSession` and
   `extension WCSession: SkipSyncSession` in `SkippedReminderSyncService`, plus
   any other protocol seams (e.g. `SpeechTranscribing`), noting how the
   concrete type is passed in production versus substituted in tests.

4. How is `EKReminder` constructed and mutated throughout the store — the
   `makeReminder` factory, `addRecurrenceRule`, `calendar`,
   `defaultCalendarForNewReminders()`, and the `isCompleted = true` mutation in
   `completeReminder` — and what object does `EKReminder(eventStore:)` require
   as a parameter?

5. How does platform-conditional compilation shape `ReminderStore` and its
   surrounding code? Trace every `#if os(...)` branch affecting EventKit usage,
   especially where watchOS makes EventKit read-only (`#if os(watchOS)`
   short-circuits in `addReminder`/`completeReminder`) versus writable
   iOS/macOS paths, and how the same source file compiles across the three
   platforms.

6. How are `ReminderStore`'s unit tests structured and executed? Describe the
   Swift Testing conventions in `SingleThreadTests/ReminderStoreTests.swift`
   (`@MainActor`, `@Suite(.serialized)`, `@testable import`, fixture helpers
   like `makeReminder`, the `#if !os(...)` platform guards) and how the
   `MakeReminderTests` static-factory seam is tested.

7. How is `ReminderStore` instantiated and wired in production? Trace
   `SingleThreadApp`'s init (including the `--ui-testing` launch-argument
   guard), `ContentView`'s initializers, and how the `onSkipSetChanged`,
   `onCompleteReminder`, and `onRemindersChanged` hooks couple the store to
   WatchConnectivity sync and widget timeline reloads.