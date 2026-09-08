# Research Questions

## Context

Focus on how a transient full-screen completion-flash animation is modelled,
triggered, and rendered across the iOS and watchOS targets of the SingleThread
app, and how the user setting that gates it is persisted and propagated
between the phone and watch. Investigate the `SingleThreadCore` package (the
feedback type and its preference store), the iOS and watch view models and
views, the WatchConnectivity sync service and its watch-side state holders,
the accessibility/reduce-motion handling, and the test seams covering each.

## Questions

1. How is the completion-flash type modelled, and where is it consumed? Inspect
   `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift` — its
   `isActive`, `duration`, `trigger()`, auto-dismiss task, and `@MainActor
   @Observable` contract. Trace how `SingleThread/ContentViewModel.swift` and
   `SingleThreadWatch/WatchReminderViewModel.swift` each own an instance, where
   `duration` is set (including `SingleThread/AppViewModel.swift`), and how the
   epoch-gating differs or is shared between the two platform view models.

2. How is the "show completion glow" user preference persisted and read?
   Inspect `ShowCompletionGlowPreference` (`init(defaults:key:)`,
   `isEnabled`/`set`, default storage `AppGroup.defaults`, and how an absent
   key resolves). Then trace how the setting surfaces in the iOS settings UI —
   `SettingsBindings`, `SettingsView`, `ReminderSettingsView` — and how the
   value reaches `ContentViewModel`. Note which iOS/watch consumers read it.

3. How is the preference and its flag propagated from the iPhone to the watch?
   Trace `SkippedReminderSyncService` — its initializer params
   (`showCompletionGlowStore`, `sendsShowCompletionGlow`), the
   `PayloadKey.showCompletionGlow` application-context entry in `pushAll()`,
   the receive path in `apply(context:)`, and the
   `onShowCompletionGlowReceived` hook. Compare which sends are turned on/off
   per platform (e.g. the watch's own app view model).

4. How does the watch consume the received flag and gate the flash? Trace
   `SingleThreadWatch/ShowCompletionGlowState.swift` (its `apply(_:)` and
   `isEnabled` publication) and `SingleThreadWatch/WatchAppViewModel.swift`'s
   wiring of `onShowCompletionGlowReceived` into that holder, plus how
   `WatchReminderViewModel.completeCurrentReminder()` consults the holder
   before calling `trigger()`. Note how this compares to the iOS side's gating.

5. How do the two platforms render the flash overlay, and how do they handle
   reduce-motion and accessibility? Compare `completionGlowOverlay` in
   `SingleThread/ContentView.swift` (opacity, `accessibilityIdentifier`)
   with the one in `SingleThreadWatch/WatchReminderView.swift` (hit-testing,
   hidden-from-accessibility, transition). Trace how each view sets its
   `.animation(_, value:viewModel.completionGlow.isActive)` and whether the
   watch wipes the glow when `accessibilityReduceMotion` is on.

6. What test seams exist for the flash and its flag, and how is the shared
   sync pipeline tested? Survey `SingleThreadTests/CompletionGlowTests.swift`,
   `ShowCompletionGlowPreferenceTests.swift`, the `--seed` / `UITestingSeed`
   launch-arg seam, the iOS `pushAll`/`receive` glow cases in
   `SkippedReminderSyncServiceTests.swift` (including `sendsShowCompletionGlow`
   on/off), and the watch `ShowCompletionGlowStateTests` / glow cases in
   `WatchSyncPipelineTests.swift`. Note how a transient (0.25s) visual effect
   is asserted, including duration-injection for near-zero timing.