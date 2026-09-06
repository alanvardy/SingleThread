# Research Questions

## Context

The SingleThread codebase has three surfaces — the iOS/macOS SwiftUI app,
the watchOS app, and the WidgetKit extension — all deriving the same
"current" Apple Reminder from a shared core `ReminderStore` over EventKit.
Focus on how the current reminder is determined and refetched, how external
state changes are observed on each platform today, and the timing,
lifecycle, and test seams available.

## Questions

1. Trace the flow that determines the "current" reminder in `ReminderStore`
   (visibleReminders / listContent / reload): what precisely does `reload()`
   re-fetch from the EventKit store, and how do complete / delete / skip
   operations cause the next reminder to take the current position?

2. What are the freshness semantics of the EventKit read path —
   `EKEventStore.fetchReminders`, `predicateForIncompleteReminders`, and
   `refreshSourcesIfNecessary`? Does each fetch return a fresh read of the
   OS Reminders database (including reminders completed or deleted on
   another device), and what is memoized or cached in `ReminderStore`
   between reloads?

3. What mechanisms currently cause the iOS/macOS app to notice that the
   displayed reminder was completed or deleted outside the app (gestures,
   scene-phase handling, reload triggers, sync messages, relaunch)? Enumerate
   every trigger that leads to a `reload()` and which of them read reminder
   completion state.

4. How does the watchOS app obtain reminder data — does it read a local
   EventKit store itself (`loadsReminders`), and how do phone-pushed
   application-context payloads (skipped identifiers, completions, likely
   sort/preferences) interact with what the watch displays? What triggers a
   phone→watch push and how is the current reminder kept consistent between
   the two devices?

5. How does the widget obtain and refresh its displayed reminder — the
   `Timeline(policy: .after(...))` refresh model, how long each
   `ReminderStore` instance lives (per-refresh construction vs persistence),
   and how intents (`CompleteReminderIntent` / `SkipReminderIntent`) cause
   the widget's timeline to reload?

6. What periodic / delayed-task patterns exist across the codebase
   (`Task.sleep` loops, `for await` SDK streams, timeline policies), how do
   long-lived tasks handle lifecycle (start/stop, scene-phase change,
   teardown on deactivation), and what are the `@MainActor` / SwiftUI
   concurrency constraints on new background work?

7. What test seams make timing and cross-device scenarios deterministic
   (settle/noopSettle, InMemoryEventStore, sync session fakes, isolated
   UserDefaults keys), and which existing tests already exercise "a reminder
   completed elsewhere is dropped from the visible list on refetch"?