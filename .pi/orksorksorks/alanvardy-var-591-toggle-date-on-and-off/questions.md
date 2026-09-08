# Research Questions

## Context

Focus on how the SingleThread app renders reminder due dates across its three
surfaces — the iOS/macOS `ContentView`, the watchOS `WatchReminderView`, and the
`NextThingWidget` — and trace how due-date data flows from `EKReminder` through
the `SingleThreadCore` package (sorting, overdue filtering, `ReminderDisplay`).
Also investigate how user preferences are persisted (via `@AppStorage`,
`UserDefaults`, and the shared App Group) and laid out in `SettingsView`, and
how those views and preferences are tested.

## Questions

1. How does `ContentView` render a reminder's due date? Trace the reminder
   card's `VStack`/`HStack` layout in the `List`, the exact
   `Text(due, style: .date)` label and its styling, how it sits relative to the
   priority marker, title, and notes, and what `if let …` conditional patterns
   gate the other optional reminder fields there.

2. How does due-date data flow through `SingleThreadCore`? Trace
   `EKReminder.dueDateComponents` → `ReminderDisplay.init(reminder:)`, how
   `ReminderSort` orders reminders by due date (dated before undated), and how
   `ReminderDateFilter`/`overdueCutoff` uses due dates when fetching reminders.

3. How are user preferences persisted and read? Trace the `@AppStorage` keys in
   `ContentView` (`appearanceMode`, `textSize`, `allowsLandscape`,
   `showMicrophoneButton`), the `AppearanceMode`/`TextSize` enum pattern
   (`String, CaseIterable` with `title`/`systemImage` computed properties), the
   difference between `AppGroup.defaults` and `UserDefaults.standard`, and how
   `AppDelegate` reads a key straight from `UserDefaults` at launch to apply
   behavior before any view appears.

4. How is `SettingsView` structured and presented? Describe its `Form` rows
   (`Picker` and `Toggle`), its `Binding`-based initializer with platform
   variants (`#if os(iOS)` gating of `allowsLandscape`), the `.toolbar` Done
   button, and how `ContentView` presents it through the gear-button
   `isShowingSettings` state and a `.sheet`.

5. How does `WatchReminderView` render a reminder and its due date, and does the
   watch target read any user preferences or shared defaults today? Trace its
   `reminderDetails` view and note whether watchOS has any settings surface or
   access to the app's persisted preferences.

6. How does the `NextThingWidget` render a due date and read persisted state?
   Trace how `NextThingProvider.makeEntry` builds a `ReminderDisplay` from
   `ReminderStore`, how `ReminderDisplay.dueDate` reaches the
   `Text(dueDate, style: .date)` in `reminderView`, and how the widget accesses
   shared `UserDefaults` (App Group) versus the app's standard defaults.

7. How are the settings preferences and reminder views tested? Trace
   `SettingsViewTests`' use of `String(describing: view.body)` to assert row
   labels, `MicrophoneToggleTests`' manipulation of `UserDefaults` keys and its
   fake `SpeechTranscribing` seam, `ReminderDisplayTests`, and what the UI-test
   accessibility audit covers.