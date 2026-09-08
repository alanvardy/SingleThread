# Research Questions

## Context

This codebase is an iOS/watchOS SwiftUI app that surfaces Apple Reminders through
EventKit. A "project" is a user's reminder list (calendar), and the app maintains an
excluded-project title set per device. That set is persisted via a thin `ExcludedProjectStore`
(UserDefaults) and shared between the phone and watch through a `SkippedReminderSyncService`
over WatchConnectivity. The phone and watch each build their own in-memory `ReminderStore`;
a `visibleReminders` filter reads an `excludedProjectTitles` set that is refreshed during
`reload()`, and both app layers wire a change hook to a push method on the sync service.

Focus on: the WatchConnectivity receive path and how (or whether) a received exclusion
reaches the live in-memory store; when `ReminderStore` re-reads its persisted title set;
what the phone actually sends when a project is toggled; how `updateApplicationContext`
context-replace semantics interact with single-key pushes and any startup/(re)connect
seeding; and what the current tests prove about the end-to-end round trip.

## Questions

1. On the watch, trace `SkippedReminderSyncService.didReceiveApplicationContext` when it
   handles `PayloadKey.excludedProjectTitles`. Does it do anything beyond saving the received
   titles to `ExcludedProjectStore` (i.e. update the live in-memory `ReminderStore.excludedProjectTitles`
   or trigger a `reload()`), or does the saved value sit unread until some later event?

2. In `ReminderStore`, where does the `excludedProjectTitles` in-memory set get its value
   from, and when is it (re)loaded from the `ExcludedProjectStore`? Is it only refreshed
   during `reload()`, and what conditions would cause the watch to re-run `reload()` for an
   externally-driven (WatchConnectivity) change rather than an on-device mutation?

3. Trace the phone-side emit: when a user toggles a project in Settings/ContentView, which
   binding/mutation method runs, which hooks fire, and precisely what payload
   `pushExcludedProjectTitles` sends to the session.

4. Characterize the WatchConnectivity push mechanics: `updateApplicationContext` is described
   as latest-wins replacing the whole context, yet `pushExcludedProjectTitles` sends an object
   with a single key. How do these combine — do other pushes each re-send their own full key
   sets, and is there any startup or (re)connect-time push that seeds current settings (or the
   excluded-project titles) to the counterpart, or is the excluded set only ever transmitted
   on a change?

5. Survey the tests: in `SkippedReminderSyncServiceTests` and `ReminderStoreTests`, which
   paths exercise the excluded-titles round trip — push payload inspection, receive-then-save
   persistence, and filter refresh? Is there any coverage that verifies a pushed exclusion
   actually reflects in a counterpart store's live `visibleReminders` filtering, as opposed to
   only persisting to UserDefaults?