# Research Questions

## Context

Focus on the SwiftUI view layer and app-entry composition across the iOS and
watchOS targets (`SingleThread/ContentView.swift`,
`SingleThread/SettingsView.swift`, `SingleThread/SingleThreadApp.swift`,
`SingleThreadWatch/SingleThreadWatchApp.swift`, `SingleThreadWatch/WatchReminderView.swift`),
the observable state layer in the `SingleThreadCore` package
(`ReminderStore`, and the watch `ShowDateState`/`ShowRecurrenceState`/`ShowAlarmsState` classes),
and the test targets that exercise this state.

## Questions

1. Which responsibilities live inside the SwiftUI view structs (`ContentView`,
   `SettingsView`, `WatchReminderView`) today — e.g. computed presentation state,
   dictation state and transitions, build of bindings from store state, and
   `.onChange` side effects — and which of these have explicit `file:line` call
   sites that call into stores, app delegates, frameworks (WidgetKit), or
   watch-sync services?

2. How does `ReminderStore` (an `@Observable` class) divide its responsibilities
   between pure state that views bind to, mutating methods (complete/delete/add/
   skip/reload), persistence stores it owns, and the closure "hooks"
   (`onSkipSetChanged`, `onRemindersChanged`, …) that the app layer wires? What
   is the full public property/method surface it exposes, and what does it
   deliberately not touch (per its docs)?

3. How are user preferences persisted and threaded into views — where do
   `@AppStorage` keys live (which suites: `.standard` vs `AppGroup.defaults`),
   how many are bound directly as `@Binding`s into `SettingsView`, and what
   `.onChange` reactions does `SettingsView`/`ContentView` entangle with
   `AppDelegate`, `WidgetCenter`, and the sync service?

4. How does the watch app share or duplicate state handling compared to iOS —
   what do the `ShowDateState`/`ShowRecurrenceState`/`ShowAlarmsState` classes
   do, how does `watchOS` branching inside `ReminderStore` behave, and where
   does watch-only logic (e.g. `#if os(watchOS)` blocks, sync push/receive
   wiring) diverge from the phone path?

5. How does the app entry point (`SingleThreadApp.init`,
   `SingleThreadWatchApp.init`) compose the store, background-image store, sync
   service registrations, widget-reload hooks, and test seams (`--seed`,
   `--ui-testing`)? Which of these cross-cutting concerns are created inline
   in `init` versus injected/owned elsewhere?

6. How are `ContentView`'s previews and the existing unit/UI tests structured
   around the store and view-computed logic (e.g. static fns like
   `emptyStateCopy`, `hasHiddenFor`, `showsActionButtons`, dictation parsing)?
   Which current tests would need to keep passing if presentation state moved
   out of the view structs?
