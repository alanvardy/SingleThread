# Research Questions

## Context

Focus on the `SingleThread` iOS/macOS reminders client (the SwiftUI app target),
its `SingleThreadCore` domain package, and the `SingleThreadWatch`,
`SingleThreadWidget`, and `SingleThreadTests` companions. Reminders come from
EventKit and are stored in `ReminderStore` (a `@MainActor @Observable` class);
the store exposes completions and skips of the current reminder, plus creation,
against an `EventKitStoring` test seam. This research maps how reminders are
written to and removed from EventKit, how the current reminder is presented and
acted upon across iOS, macOS, the watch app, and the widget extension, how
state changes are persisted and relayed between surfaces, and how mutations are
tested and covered by accessibility checks. No behavior changes are proposed
here — the goal is a neutral map of the existing mutation, presentation,
persistence, sync, and test seams.

## Questions

1. What write and removal operations does the EventKit seam expose, and how do
   they map onto a reminder's lifecycle? Trace the `EventKitStoring` protocol in
   `EventKitStoring.swift` (authorization, calendars, `save`, `makeReminder`,
   `fetchReminders`, `refreshSourcesIfNecessary`), its `EKEventStore` extension,
   and every call site — especially how `ReminderStore.completeReminder` mutates
   an `EKReminder` (`isCompleted = true` then `save(commit:)`). Does the EventKit
   `EKReminder` / `EKEventStore` interaction model expose any way to remove or
   delete an item, and how would recurring reminders (added via
   `addRecurrenceRule`) behave under such a removal?

2. How is the current reminder surfaced and acted upon on each surface? Trace
   `ReminderStore.visibleReminders` (the skip/`excluded` filter plus
   `ReminderSort.areInIncreasingOrder`) and every consumer of `.first` — the
   iOS `.swipeActions` (leading = Complete, trailing = Skip) and
   `contextMenu`, the macOS `actionButtons` HStack (Complete/Skip with
   keyboard shortcuts), `bottomBar`, the widget provider, and the watch
   `WatchReminderView`. For each, note the exact `Button`/gesture wiring and
   how the action reaches the store.

3. How are reminder mutations funneled through the store, and how do state
   changes reach the other surfaces? Trace `completeCurrentReminder` /
   `completeReminder`, `skipCurrentReminder(Immediately)`, `addReminder`, and
   `reload()`, noting the `@MainActor` concurrency boundary, the
   `eventKitSettleDelay` sleep used after writes, and the hooks
   (`onRemindersChanged`, `onSkipSetChanged`, `onCompleteReminder`) that the
   iOS app wires to push updates via `SkippedReminderSyncService` /
   `WatchConnectivity` in `SingleThreadApp.swift`. Also trace the
   `CompleteReminderIntent` / `SkipReminderIntent` in `ReminderIntents.swift`
   used from the widget, and whether a parallel add/complete/skip path exists
   for a future mutation.

4. What does the persistence layer look like across EventKit and App Group
   UserDefaults? Trace `SkippedReminderStore` + `ReminderSkipLogic` (the skip
   list), `ExcludedProjectStore`, `SortOptionStore`, and `AppGroup.swift`
   (`UserDefaults.defaults` for the shared skip list), and clarify which stores
   each process (iOS app, widget extension, watch app, test fakes) can actually
   read/write. Note where a removed reminder could appear in `visibleReminders`
   until a `reload()` and how `showsUndatedReminders` / the date predicate in
   `reload()` affect what is fetched.

5. What UI composition and accessibility conventions govern presenting the
   reminder card and its actions? Read `ReminderCardView.swift` and the relevant
   parts of `ContentView.swift` — the card layout, priority colors, the
   `.swipeActions(edge:)`, `.contextMenu`, `bottomBar`, `accessibilityLabel` /
   `accessibilityAddTraits`, `keyboardShortcut`, and how iOS differs from macOS.
   Identify the established pattern for adding a button/gesture (label, tint,
   systemImage, traits, shortcut) so a new destructive action fits the existing
   structure.

6. How are these mutations and UI actions tested and audited? Trace
   `ReminderStoreTests.swift` (the recording `EventKitStoring` fake and
   `makeReminder` factories, how `completeCurrentReminder`, `skip`, and `add`
   are exercised), `ReminderSkipTests.swift`, `SettingsViewTests.swift`, the
   app's `@AppStorage` / SwiftUI preview conventions, and the
   `SingleThreadUITests` accessibility audit. Identify which behavior changes
   (store methods, hooks, reload) are unit-testable without a real EventKit and
   which require UI/XCTest coverage.