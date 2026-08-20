# Research Questions

## Context

Focus on the SingleThread iOS app's main view hierarchy and bottom bar,
the settings surface and its persisted preferences, the shared
`ReminderStore` action API in SingleThreadCore, and the watchOS action
buttons plus their test coverage. Key areas: `SingleThread/ContentView.swift`,
`SingleThread/SettingsView.swift`, `SingleThreadCore/Sources/SingleThreadCore/`
(`ReminderStore.swift`, `AppGroup.swift`, `ReminderSkip.swift`),
`SingleThreadWatch/WatchReminderView.swift`, and the test suites under
`SingleThreadTests/`, `SingleThreadUITests/`, and `SingleThreadWatchUITests/`.

Do NOT read the artifact directory or this repo's QRSPI folders for this
task's own documents — those describe what is being built.

## Questions

1. How is the iPhone view's bottom bar composed in `ContentView.swift`?
   Trace every branch where `bottomBar` is rendered (empty state, has-reminder
   state, all-skipped state) and describe the `micButton` and its surrounding
   `VStack`/`HStack` layout. What state (`isDictating`, `creationFeedback`,
   `dictationError`, `canDictate`, `showMicrophoneButton`) controls which
   bottom-bar children appear, and how is the bottom bar positioned relative
   to the scrolling reminder list?

2. How does the watch app render and style its action buttons in
   `WatchReminderView.swift`? Compare the Complete/Skip buttons (labels,
   `systemImage` names, `.tint` colors, `.labelStyle`, icon-only framing,
   accessibility label/traits) against the macOS `actionButtons` block in
   `ContentView.swift` and the iOS swipe/context-menu actions — what exactly
   do they call on the store and what visual/label pattern do they share?

3. How is the Settings menu structured and how are its preference toggles
   wired? Trace `SettingsView.swift` and its `ContentView` call site: how are
   toggle bindings declared (`@Binding` vs `@AppStorage`), passed between the
   two views, and persisted to `UserDefaults` — specifically the difference
   between `.standard` and `AppGroup.defaults`? Which existing toggles (e.g.
   `showMicrophoneButton`, `showDate`, `showUndatedReminders`) follow which
   persistence path, and how is the settings sheet opened/dismissed?

4. How do `ReminderStore`'s action methods for the current reminder behave?
   Trace `completeCurrentReminder()`, `skipCurrentReminder()`,
   `skipCurrentReminderImmediately()`, and `deleteCurrentReminder()` — their
   signatures (async vs sync), the store state they read/mutate (visible
   reminders, skipped IDs), and how they communicate with the rest of the
   app (reminder-changed hooks, WatchConnectivity, AppGroup persistence).

5. How is the skipped-reminder identifier persisted and synced across the
   phone, watch, and widget? Trace `ReminderSkip.swift`,
   `SkippedReminderSyncService.swift`, and `AppGroup.swift` — what key/storage
   mechanism holds the skipped list, how the app and watch exchange it over
   WatchConnectivity, and how a skip on one device is observed on siblings.

6. What tests cover these areas? Map `SettingsViewTests.swift`,
   `MicrophoneToggleTests.swift`, `ReminderStoreTests.swift`
   (`skipCurrentReminder*`/`completeCurrentReminder*`), the UI test suites
   (accessibility audit, `--ui-testing` seam, `SingleThreadUITests.swift`,
   `SingleThreadWatchUITests.swift`), and how they inject fake transcribers
   or a pre-populated store to drive the view body.