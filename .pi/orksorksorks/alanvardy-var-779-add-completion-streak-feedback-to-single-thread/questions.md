# Research Questions

## Context

This is a Swift/Xcode monorepo (Swift 6, EventKit-backed reminders): a single
iOS app target, a SingleThreadCore SPM package holding the ReminderStore model
with skip/completion counters, a watchOS app that syncs with the phone over a
shared App Group UserDefaults suite, and Swift Testing unit tests plus XCTest
UI tests. Researchers should focus on the reminder completion flow, the
persisted counters shared with the watch, transient UI feedback surfaces, date
semantics, and the test infrastructure that covers these areas. All codebase
reading happens here; answer only with what exists today, with file:line
references.

## Questions

1. Trace the complete/clear flow in ReminderStore: what happens from the
   moment completeReminder is invoked — completionCounter changes, undo
   retention, watch-receive paths, which hooks fire — and how do the
   single-card UI view models observe those state changes?

2. How does the AppGroup.defaults persistence suite work, and how do values
   round-trip between the phone and watch? Trace SkippedReminderSyncService
   pushAll and apply: which values are pushed, what are the payload keys,
   how are skipCounts and completionCount propagated, and what is the
   watch-side receive wiring (WatchAppViewModel wireStateReceiveHooks and
   related Show*State holders)?

3. What transient UI feedback surfaces exist today — completion glow, skip
   nudge banner, creation feedback bubble, undo overlay, empty-state card?
   For each: where it is defined, what triggers it, how it renders and
   dismisses itself, and any preferences controlling it.

4. How does the codebase compute today and calendar-date windows? Trace
   ReminderDateFilter, how reminder dates are parsed and compared, timezone
   handling, and any existing streak-like or consecutive-day counting logic
   anywhere in SingleThreadCore, the iOS app, or the watch app.

5. What test infrastructure covers ReminderStore persisted state: the
   InMemoryEventStore, TestFixtures, the --seed UITestingSeed seam,
   CompletionCounterStoreTests, SkipCountStoreTests, AppGroupTests, and the
   watch sync pipeline tests? How do tests isolate UserDefaults suites and
   assert on store state changes?