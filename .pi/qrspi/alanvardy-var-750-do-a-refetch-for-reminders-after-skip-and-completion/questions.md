# Research Questions

## Context

SingleThread is an iOS/watchOS reminder app that reads Apple Reminders through
EventKit. The core store (`ReminderStore` in the `SingleThreadCore` package)
fetches reminders, exposes them to SwiftUI views, and mutates them through
complete/skip/delete actions on both platforms, with phone↔watch sync over
WatchConnectivity. Focus on how the store reads and reconciles its in-memory
list against the event store, how the two platforms mutate it, and how tests
drive these flows.

## Questions

1. **Fetch/reload path**: How does the store re-read reminders from the event
   store (`ReminderStore.reload()` and the low-level `fetchReminders` bridge)?
   What timing guarantees exist around EventKit writes (e.g. the 200 ms settle
   delay before re-fetch), and does the app observe any EventKit change
   notifications (e.g. `EKEventStoreChanged`), or is every refetch driven by an
   explicit `reload()` call site? Enumerate every call site that triggers a
   reload on iOS and watchOS.

2. **Completion flow across devices**: Trace what happens on completion on each
   platform — the iOS branch (EventKit save + reload), the watchOS branch
   (in-memory array removal + relay message), and what the phone does when it
   receives a relayed completion from the watch (`onCompleteReminderReceived`).
   Where in this flow could the same reminder be completed more than once, and
   what state (in-memory list, EventKit, undo store, completion counter) is
   mutated at each step?

3. **Skip flow and skip-state persistence**: How does skipping work end to end —
   `skipCurrentReminder()` vs the synchronous `skipCurrentReminderImmediately()`,
   the App Group-backed `SkippedReminderStore`, and how `ReminderSkipLogic.resolve`
   prunes stale identifiers during a reload? When the watch pushes skipped
   identifiers to the phone, what does the phone do with them, and which
   `SkippedReminderSyncService` receive handlers are wired up on each platform
   (`onSkippedIdentifiersReceived`, `onCompleteReminderReceived`)?

4. **State observation and list refresh triggers**: How do the iOS and watchOS
   views observe the reminder list (the `@Observable` store, derived
   `visibleReminders` property), and what is the full set of triggers that can
   change or re-fetch it (pull-to-refresh, scene-phase changes, mutation paths,
   WatchConnectivity context updates, widget timeline refreshes)? Is there any
   interval-based, notification-driven, or on-foreground refresh mechanism?

5. **Concurrency model**: What actor-isolation model governs the store and its
   mutations (`@MainActor` defaults, Swift 6 language mode), and how are
   asynchronous EventKit calls bridged (continuations, resumption gates)? How
   do the mutation paths guard against races — e.g. the `skipGeneration`
   mechanism, off-main fetch completion, and re-entrancy between a deferred
   skip write and a subsequent reload?

6. **Test infrastructure for store mutations**: How do `InMemoryEventStore` and
   the `--seed` / `--ui-testing` launch-arg seams model EventKit behavior (does
   `fetchReminders` filter out completed reminders, and how are saves/removes
   reflected in subsequent fetches)? Which existing unit tests
   (`ReminderStoreTests`, `ReminderSkipTests`, `SkippedReminderSyncServiceTests`)
   and UI tests cover complete and skip, and what do they currently assert about
   the store's list state after those actions (`loadsReminders` usage)?