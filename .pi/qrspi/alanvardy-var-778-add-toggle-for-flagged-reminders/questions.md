# Research Questions

## Context

Research the SingleThread codebase: the `SingleThreadCore` package (reminder data model, queue composition, preference stores), the iOS app's settings UI machinery, the cross-target persistence/sync layer, and the unit + UI test seams for reminder filtering and settings toggles. Focus on what exists, how it works, and the conventions already in place.

## Questions

1. **Reminder data model & per-reminder attributes**: What fields does the EventKit `EKReminder` type expose (title, notes, due date, calendar, priority, …), and where is it defined (SPM package source vs local bindings)? How are those fields mapped into the app's `ReminderDisplay` DTO, and what are the exact semantics of `ReminderPriority` (RFC-5545 `priority` values, level/marker/rank mapping) relative to any other importance/flag-like concept a reminder might carry?

2. **Queue composition & filter layers**: How is the visible reminder queue built — trace `ReminderStore.visibleReminders`, `reload()`, and the EventKit fetch predicate (`predicateForIncompleteReminders`, `ReminderDateFilter`)? Which filters apply in-memory vs at the fetch layer, how are the existing filters (skipped IDs, excluded list titles, undated-window, sort option) combined and ordered, and what state mutations cause re-computation/refetch?

3. **Settings toggle end-to-end mechanics**: How does a user-facing toggle or picker in the Settings sheet flow to effect, and back? Trace `SettingsBindings`, the `@AppStorage`-backed declarations and writebacks (`ContentView+Settings.swift`, `ContentView.swift`), the `SettingsViewModel`, and how open/close of the sheet and app launch map stored values into UI state. Contrast how a display-only bool (`showCompletionGlow`) differs from a list-filtering toggle (`showUndatedReminders`) in this flow.

4. **Preference persistence & defaults**: How are individual preference values stored and loaded — the `UserDefaults` suite (`AppGroup.defaults`), each per-preference store wrapper (`SortOptionStore`, `ShowUndatedRemindersPreference`, `ShowCompletionGlowPreference`, …), their load-time default handling for absent keys, and where the stores are wired in at startup (`AppViewModel`)?

5. **Cross-target sync & consumers**: Which targets consume list-affecting preferences (iOS app, watch app, widget extension), how does `SkippedReminderSyncService.pushAll`/`apply` serialize and re-apply preference keys (payload keys, per-key `sends*` flags, receive-side store hooks), and how does each consumer (e.g. `NextThingWidget`, `WatchAppViewModel`) read and re-apply preferences at launch?

6. **Test seams for filtering & toggles**: What unit-test patterns cover queue filtering/sorting and preference stores (`ReminderStoreTests` fixtures, Swift Testing), and what UI-test seams cover settings toggles end-to-end (`--seed`/`InMemoryEventStore` JSON schema, `flipToggle`/`assertTogglePersists` harness helpers, persist-across-relaunch flows, `resetPersistedState` key list)? What conventions apply when a new persisted key or a new queue filter is introduced — key isolation in seeded tests, default-value assertions, and both unit + UI coverage?