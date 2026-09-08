# Research Questions

## Context

Focus on how list/reminder "content state" is modeled and consumed across the
three UI targets in this repo. Four relevant areas: the widget target's
`NextThingWidget.swift` (its `NextThingEntry.State` enum and the view that
renders it), the iOS app's `ContentView.swift` / `ContentViewModel.swift`
(empty and all-done rendering plus the copy builders), the watch target's
`WatchReminderView.swift` / `WatchReminderViewModel.swift`, and the
`SingleThreadCore` package where shared types and strings live. Also relevant
is the shared `ReminderStore` in Core and its derived state (`allSkipped`,
`hasHidden`, `visibleReminders`).

## Questions

1. What exactly is the widget's `NextThingEntry.State` enum — its declaration,
   every case and payload, how `NextThingProvider` constructs it (including
   the exact branch order between empty vs all-done vs reminder), and how the
   widget view exhaustively switches on it? Where does `NextThingEntry` get
   consumed outside its own file?

2. How do the iOS app and the watch each compute their list-content branch
   order, and what is the precise relationship/order between the "all-skipped"
   check, the "empty reminders" check, the "first visible reminder" branch,
   and any auth gate? Where are the empty and all-done copy strings and icons
   defined, and how are the two targets' empty/all-done semantics currently
   identical despite the different branch order?

3. What are the conventions for adding a shared, non-persisted type to
   `SingleThreadCore` that multiple targets consume? Specifically: how does an
   enum that carries no rawValue or persistence behave (e.g. `ReminderPriority.Level`
   vs persisted `SortOption`), what modifiers/visibility do `enum` and `struct`
   types in Core use, and does Core stay SwiftUI-free while carrying types that
   render `AttributedString` presentation values?

4. What is the closest existing precedent for a shared Core enum that is
   exhaustively switched by more than one target? Trace how
   `ReminderPriority.Level` (or `ReminderDisplay`) is declared in Core and
   consumed by iOS and watch — including how an exhaustive switch with no
   `default` is kept exhaustive when a new case is added, and how missing cases
   surface in builds/lints.

5. What are the exact semantics and validity constraints of `ReminderStore`'s
   derived state that feeds all three targets — `allSkipped`, `hasHidden`, and
   `visibleReminders`? In particular, the guarantee that `allSkipped` implies a
   non-empty store (`ReminderStore.swift:138-140`), and how `hasHidden` differs
   in meaning between the iOS empty-state copy and the widget's
   `State.empty(hasHidden:)` payload.

6. How are the copy strings (`SharedStrings.allDone`, `noRemindersYet`,
   `nothingDueRightNow`, `noReminders`) and their icons centralized in the
   Core `SharedStrings` enum and `Localizable.xcstrings` catalog, and how do
   each target's UI tests depend on the current empty/all-done branch ordering
   (e.g. which tests assert all-done hides the bottom bar, or "Nothing due"
   when `hasHidden` is seeded)?

7. What existing unit/UI test coverage exercises the widget's
   `NextThingEntry.State`, the iOS empty/all-done logic, and the watch's
   all-done/no-reminders ordering — which test files and cases, and how are
   exhaustive-switch coverage and enum-equality/round-trip tested in this repo?