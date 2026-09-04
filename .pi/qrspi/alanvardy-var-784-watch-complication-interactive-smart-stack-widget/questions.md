# Research Questions

## Context

This research surveys the SingleThread iOS + watchOS codebase: the reminder model and visibility pipeline in the `SingleThreadCore` SPM package, the existing WidgetKit widget extension and its App Intents, the WatchConnectivity sync service shared between phone and watch, the watchOS app's rendering and state derivation, and the project/CI configuration for the watch and widget targets. Focus on how these pieces behave today — data flow, lifecycle, and test seams — rather than on any new capability.

## Questions

1. **Visibility pipeline**: Trace how `ReminderStore.visibleReminders` is derived — the skip/excluded-list/undated filters, `ReminderSort` ordering, the `reload()` time-window filter, and the `hasHidden` / `allSkipped` / `canMutate` state semantics. How is a `ReminderDisplay` value constructed from an `EKReminder`, and which of these types and helpers are `public` and thus usable from widget and watch targets?

2. **Widget extension architecture**: How do `NextThingWidget`'s timeline provider and entry state machine work — fresh `ReminderStore` per render, `EKEventStore.authorizationStatus` gating, the fixed `Timeline.policy.after` refresh interval, and the empty/`allDone`/`noAccess` state branches? How do `CompleteReminderIntent` / `SkipReminderIntent` perform (fresh store, reload, the synchronous skip variant), and what triggers the iOS-side `onRemindersChanged` → `WidgetCenter.reloadAllTimelines()` reload?

3. **WatchConnectivity sync**: What state does `SkippedReminderSyncService` push between phone and watch (payload keys, latest-wins semantics, `pushAll()`), what are the receive hooks and how are they wired on each side, and how do the watch→phone `requestCompleteReminder` / `requestDeleteReminder` relays work? What data is explicitly *not* on the wire, and how does each side derive its reminder list (local EventKit? AppGroup context? `.standard` vs suite defaults on watchOS)?

4. **Watch app presentation and state derivation**: What are the exact empty-state branches and strings in `WatchReminderView` (`noAccess`, `allSkipped` → "All Done", `noRemindersState`), how does `WatchReminderViewModel` pick the current reminder and refresh (clearSkipped, minimum display duration, completion ghost), and what composition-root wiring does `WatchAppViewModel` perform — including which UserDefaults stores each shared preference reads from?

5. **Project and CI plumbing**: How are the `SingleThreadWidget`, `SingleThreadWatch`, and test targets configured in `project.pbxproj` — supported platforms, deployment targets, bundle IDs, embedding (watch app into phone app, widget extension), and entitlements? How does `scripts/test.sh` enumerate expected pbxproj deployment-target literals, and how do the CI watch build and `watch-ui-tests` jobs create/run simulators and map to Makefile targets?

6. **Test seams and formatting utilities**: What testing patterns exist for Core logic (Swift Testing with `InMemoryEventStore` / noop-settle, `ReminderIntentsTests`, watchOS `ReminderStoreWatchTests` for pending completions) and for the watch app (the `--ui-testing` seam: `uiTestingStore`, priority/excluded/gated flags, live-excluded delivery)? What formatting/string utilities already exist (priority markers, recurrence summary, attributed-title/notes formatting, `SharedStrings`) and what does not exist yet (e.g. any relative due-date formatting), and how are these strings and formatters shared across targets?