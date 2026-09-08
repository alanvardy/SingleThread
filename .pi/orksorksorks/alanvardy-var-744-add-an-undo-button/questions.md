# Research Questions

## Context

This repo is a SwiftUI reminders app with three runtime surfaces — a shared
`SingleThreadCore` package, an iOS app, and a watchOS app — plus a widget.
Focus areas: the reminder completion flow (UI → ReminderStore → EventKit), the
iOS main-screen UI composition (overlays, corner controls, control plates),
the settings/preferences infrastructure (interface settings menu, bindings,
`@AppStorage`), shared App Group `UserDefaults` persistence patterns,
transient in-memory state patterns, the phone↔watch sync service, and the
unit/UI test seams used to exercise these flows. Describe what exists and how
it works; do not propose changes.

## Questions

1. **Completion flow.** Trace the reminder completion action end to end: every
   UI entry point (iOS leading swipe action, bottom action cluster, watch
   `Complete` button, watch→phone relay), through
   `ReminderStore.completeReminder(identifier:)`, to the EventKit write and the
   subsequent reload. What state changes happen (list contents, counters,
   persisted IDs), what hooks fire (`onCompleteReminder`, `onRemindersChanged`,
   …), what settle-delay/reload logic exists, how does the
   `canMutate`/freemium gate interact, and what happens to the completed
   reminder in `visibleReminders`?

2. **Settings toggle plumbing.** How is an existing interface-settings toggle
   (e.g. "Show completion glow" or "Show action buttons") built and wired?
   Trace it from its `@AppStorage` declaration in `ContentView`, through
   `SettingsBindings` and `SettingsViewModel`, into `InterfaceSettingsView`
   where it renders, and to any Core preference store (init with defaults key,
   `load()`/`save()`). What are the conventions for a new toggle — key naming,
   default values, watch sync involvement, and entries in
   `UITestingSeed.resetPersistedState()`?

3. **App Group persistence patterns.** How does shared persistence in
   `AppGroup.defaults` work, and what patterns exist for persisting collections
   of reminder identifiers (e.g. `SkippedReminderStore`'s
   `skippedReminderIdentifiers`)? Cover key naming, `load()`/`save()`,
   pruning/consistency logic in `ReminderStore.reload()`, the `.standard`
   fallback, and how persisted state is reset for test runs.

4. **Main-screen UI composition.** Map the root structure of `ContentView`:
   the `ZStack` layering, the settings gear overlay (`.overlay(alignment:)`,
   padding, `controlPlate()` modifier, accessibility label), which corners are
   currently occupied or free, and the conventions for adding and styling a new
   main-screen control. Also describe how transient feedback overlays (e.g.
   `completionGlow`) are triggered, dismissed, and gated.

5. **Transient in-memory state.** What patterns exist in `SingleThreadCore`
   for transient, instance-level state that tracks recent activity? Examine
   `CompletionGlow` (injectable duration, auto-dismiss) and
   `CompletionCounterStore` (monotonic count, gating only, never decremented):
   how are they injected into/observed by `ReminderStore`, the view models, and
   tests?

6. **Phone↔watch sync.** How do reminder mutations sync between watch and
   phone via `SkippedReminderSyncService`? Distinguish latest-wins
   `updateApplicationContext` payloads from request/response `sendMessage`
   payloads (`completeReminderIdentifier`, `deleteReminderIdentifier`), the
   `PayloadKey` enum, and the hook wiring on both sides (`AppViewModel`,
   `WatchAppViewModel`). What are the established patterns for syncing a new
   per-instance or per-reminder piece of state?

7. **Test infrastructure.** What conventions cover completion and settings
   flows? Describe the unit-test style (Swift Testing, fixtures over
   `InMemoryEventStore`, gate tests with seeded counters) and the iOS UI-test
   style (the `--seed '<json>'` launch-arg seam, `flipToggle` helper, how
   `UITestingSeed.fromLaunchArguments` builds a seeded store without EventKit,
   accessibility audit), noting which suites would be affected by a change to
   the completion flow or the interface settings menu.