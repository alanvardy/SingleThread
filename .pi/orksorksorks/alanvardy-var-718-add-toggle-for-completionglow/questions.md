# Research Questions

## Context

Focus on how the SingleThread app models a transient visual completion
feedback, how the "show X" display preferences are persisted and surfaced in
settings, and how those preferences are propagated from the iPhone to the
Apple Watch. Investigate the `SingleThreadCore` package (the feedback type and
the `ShowDatePreference`-style preference stores), the iPhone settings UI, the
WatchConnectivity sync service, the watch-side state holders, and how all of
these are tested.

## Questions

1. How is the completion feedback refactorable, and how is it consumed today?
   Inspect `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift`
   (its `isActive`, `duration`, `trigger()`, and auto-dismiss task). Trace how
   `SingleThread/ContentViewModel.swift` and
   `SingleThreadWatch/WatchReminderViewModel.swift` each own an instance and
   call `trigger()` on successful completion, and how `SingleThread/ContentView.swift`
   and `SingleThreadWatch/WatchReminderView.swift` gate their
   `completionGlowOverlay` subview.

2. How are the "show X" display preferences persisted and modelled? Trace the
   preference structs in `SingleThreadCore` — `ShowDatePreference`,
   `ShowListPreference`, `ShowRecurrencePreference`, `ShowAlarmsPreference` —
   including their `init(defaults:key:)`, `isEnabled`/`set`/`save` members,
   default storage (`AppGroup.defaults`), and the corresponding `@AppStorage`
   keys in `SingleThread/ContentView.swift`. Note which preferences are
   iOS-only versus shared.

3. How is the iPhone/macOS settings surface structured for these display
   preferences? Trace `SettingsBindings`, `SettingsView`, and
   `ReminderSettingsView` (their `Toggle` rows and `.onChange` hooks), how each
   toggle routes through `SettingsViewModel.showPreferenceChanged()` (which
   reloads widget timelines), and how the platform `#if` gating splits iOS-only
   from shared rows.

4. How are display preferences propagated from the iPhone to the watch? Trace
   `SkippedReminderSyncService` — its initializer params (`showDateStore`,
   `sendsShowDate`, etc.), `pushAll()` building the ApplicationContext
   payload, the `PayloadKey.*` strings, the receive-side `apply()` which
   persists values and fires hooks like `onShowDateReceived`, and how
   `AppViewModel.setupSyncObservation` and
   `handlePreferencesChanged()` trigger a push when App Group defaults change.

5. How does the watch consume and render these preferences? Trace
   `WatchAppViewModel` composition (building `ShowDateState`,
   `ShowListState`, etc., passing them into `WatchReminderViewModel`), the
   `@Observable` `Show*State` holder `.apply(_:)`, and how
   `WatchReminderViewModel`/`WatchReminderView` read that state to gate the
   rendered elements.

6. How are the completion-feedback and display-preference behaviors tested?
   Trace `SingleThreadTests/CompletionGlowTests.swift` (state machine plus
   `ContentViewModel` wiring suites), the preference unit tests
   (`ShowDatePreferenceTests`, `ShowAlarmsPreferenceTests`, etc.), the
   SettingsView / SettingsViewModel test approach, and the sync tests
   (`SingleThreadTests/SkippedReminderSyncServiceTests.swift`,
   `SingleThreadWatchTests/WatchSyncPipelineTests.swift`). Note what fixtures
   and seams (`InMemoryEventStore`, fake transcribers) are available for
   exercising these flows.

7. Which surfaces consume this completion feedback, and which do not? Confirm
   the widget (`SingleThreadWidget/NextThingWidget.swift`) and the macOS app
   do (or do not) render the glow or share the phone's display-preferences
   model, so any change is scoped to the right targets.