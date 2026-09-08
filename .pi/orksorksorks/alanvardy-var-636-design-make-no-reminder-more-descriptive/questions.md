# Research Questions

## Context

The iOS app (`SingleThread/ContentView.swift`) renders a set of placeholder
states in its main reminder view — one for when the fetched reminder list is
empty, and another for when all fetched reminders are hidden — alongside an
authorization-gated state. These states are driven by data computed in the
shared `ReminderStore` (in `SingleThreadCore`), mirrored by companion surfaces
(the watch app and widget extension), and exercised by previews, unit tests,
and UI tests. This research maps how these placeholder states are rendered,
what store data determines them, how they surface consistently across
platforms, and how they are previewed and tested.

## Questions

1. How does `ContentView` render its placeholder states? Trace the `reminderList`
   branches for "All Done" and "No Reminders" — what layout primitives compose
   them (`ScrollView`, `GeometryReader`, `frame(minHeight:alignment:)`,
   `ZStack`, `bottomBar`)? What is `ContentUnavailableView`, where is it
   defined, and how is it used elsewhere in the codebase?

2. What store state distinguishes the empty state from the all-hidden state?
   Trace how `ReminderStore` populates `reminders`, `visibleReminders`,
   `skippedIDs`, `excludedProjectTitles`, and any `availableProjects`, how
   `reload`/`reload(clearSkipped:)` updates them, and what conditions each
   state's branch actually tests.

3. How are the placeholder states previewed, unit-tested, and accessibility-
   audited? Which `#Preview` declarations build `ContentView(loadsReminders: false)`,
   which Swift Testing and UI tests exercise the empty state or its body string,
   how `--ui-testing` alters initial state, and whether any existing assertions
   check the placeholder text strings.

4. How do the companion surfaces represent the same placeholder states? Compare
   the "No Reminders" and "All Done" presentments in `WatchReminderView` and
   `NextThingWidget` (string literals, layout, icon/system imagery, refresh
   affordances) with the iOS app's presentation, noting where they diverge.

5. What actions are available from each placeholder state? How does the
   pull-to-refresh affordance invoke `reload` versus `reload(clearSkipped:)`,
   how does `bottomBar`/dictation (mic) appear in the empty state, and how does
   the authorization flow (`.fullAccess` vs. missing access) initially gate
   entry into these states?