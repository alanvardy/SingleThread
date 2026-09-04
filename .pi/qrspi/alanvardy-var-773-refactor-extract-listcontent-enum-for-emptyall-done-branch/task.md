# Task: Refactor — extract shared ListContent enum for empty/all-done branch ordering

Extract the widget's existing `NextThingEntry.State` shape into a shared
`ListContent` enum in `SingleThreadCore` with the cases
`noAccess`, `empty(hasHiddenSubtle:)`, `allDone`, `reminder(ReminderDisplay)`.
All three UI targets (iOS app, widget, watch) will consume the same enum and
render via exhaustive `switch`, eliminating the current per-target divergence
in empty-state vs all-skipped branch ordering. Widget behavior must remain
unchanged; iOS and watch empty/all-done copy semantics must stay identical.

Identified from VAR-773 (VAR-759 state audit, T2.2 + Enum Sketch 3):
iOS checks `allSkipped` before the empty-state copy
(`ContentView.swift:358-455`); the widget checks `isEmpty` before `allSkipped`
when building `NextThingEntry.State` (`NextThingWidget.swift:62-94`); the watch
has its own ordering (`WatchReminderView.swift:77-91`). Semantically equivalent
today (`allSkipped` requires non-empty, `ReminderStore.swift:138-140`) but
structurally divergent, so a future change to one ordering could miss the
others.