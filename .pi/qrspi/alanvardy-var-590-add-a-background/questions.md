# Research Questions

## Context
Focus on the iOS app target (`SingleThread/`), the `SingleThreadCore` SPM
package, and how the two share state. Relevant areas: the main screen's view
hierarchy and appearance handling, any networking or remote-data code,
persistence mechanisms (UserDefaults suites and any file-system use), the
settings UI and its cross-surface sync (App Group defaults + WatchConnectivity),
error/fallback handling patterns, and the unit/UI test seams.

## Questions
1. How is the root view of the main screen structured (`ContentView.body`),
   including layering, safe-area handling, and how the Appearance mode system
   colors/styles it? Where exactly do full-screen visual layers sit in that
   hierarchy?
2. What networking or remote-data-loading code exists anywhere across all
   targets (app, Core package, watch, widget), and what async/background-work
   patterns (Task, actors, timers, lifecycle hooks like scenePhase) does the
   codebase currently use that remote fetches would follow?
3. What persistence mechanisms exist today — every UserDefaults wrapper/store
   in `SingleThreadCore`, the App Group suite usage, and any file-system or
   binary data storage — and how are stored values injected for previews and
   tests?
4. How are settings toggles defined end-to-end: their declaration in
   `SettingsView`, the `@AppStorage` bindings owned by `ContentView`, which
   keys sync to watch/widget via App Group defaults and
   `SkippedReminderSyncService` application contexts, and where custom footer
   or attribution-style text appears in the settings menu?
5. How does the codebase handle operation failures and fallback display states:
   error logging chokepoints, the typed-error pattern in dictation, empty-state
   views on the main screen, and how a "keep previous value on failure"
   behavior would map onto existing store patterns?
6. How are new logic and new user-facing flows tested: protocol-seam dependency
   injection (`EventKitStoring`, `InMemoryEventStore`), the `--seed` UI-test
   launch-argument seam, `UITestingSeed.resetPersistedState()`, and what the
   accessibility audit requires of layered/overlapping visuals?
