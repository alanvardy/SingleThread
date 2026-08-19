# Research Questions

## Context

Focus on the `SingleThread` iOS/macOS app target and the shared
`SingleThreadCore` package. Trace how reminders are ordered for display and how
that ordered list becomes the single "current" reminder shown to the user; how
the app's settings preferences are modeled, persisted, and wired into the
settings screen; how ordering and preferences reach secondary surfaces (widget,
watch, App Intents); how persisted values are read outside of SwiftUI bindings;
how the set of eligible reminders is filtered before ordering; and how all of
this is tested and previewed.

## Questions

1. How is the display order of reminders computed today? Trace
   `ReminderSort.areInIncreasingOrder` end to end: its comparison tiers
   (priority rank, due date, title), the `ReminderPriority.rank(for:)` mapping
   it depends on, and every call site that invokes it.

2. How does the ordered list become "the current reminder"? Trace
   `ReminderStore.visibleReminders` (its filter plus sort) and every consumer
   that reads `.first` from it — `completeCurrentReminder`,
   `skipCurrentReminder(Immediately)`, `ContentView`, `WatchReminderView`, the
   widget provider, and the App Intents — noting which run in the same process
   versus separate extension processes.

3. How are the existing settings preferences modeled and wired? Trace the
   `AppearanceMode` and `TextSize` enums (raw type, conformances, and their
   computed `colorScheme` / `dynamicTypeSize` / `title` / `systemImage`
   properties), the `@AppStorage` keys declared on `ContentView`, how they are
   passed as `Binding`s into `SettingsView`, and the platform-conditional
   initializers and `Picker`/`Toggle` rows inside the `Form`.

4. How and where are persisted preference values read outside of SwiftUI
   bindings? Trace `AppDelegate.applyLock` and
   `supportedInterfaceOrientationsFor` reading `UserDefaults.standard` directly,
   the `@AppStorage` string-key literals, and the role of `AppGroup.defaults`
   for the skip list — clarifying which UserDefaults suite each reader (app,
   widget extension, watch) can actually access.

5. How is the eligible reminder set determined before ordering? Trace
   `reload()`'s EventKit predicate (`ReminderDateFilter.overdueCutoff()` /
   `endOfToday()`), how the skip list is resolved and applied
   (`ReminderSkipLogic`, `SkippedReminderStore`), and how skipped-versus-visible
   filtering composes with the sort in `visibleReminders`.

6. How are ordering and settings behavior tested and previewed? Trace
   `ReminderSortTests` in `SingleThreadTests/ReminderSkipTests.swift` (the
   `makeReminder` and `titles(of:)` helpers), the Swift Testing conventions in
   `SettingsViewTests` (`String(describing: view.body)` assertions), and the
   enum-value tests for `AppearanceMode` and `TextSize`.