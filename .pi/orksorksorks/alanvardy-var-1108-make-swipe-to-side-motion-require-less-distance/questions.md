# Research Questions

## Context

Focus on the iOS reminder app UI under `SingleThread/` (and its supporting
tests under `SingleThreadTests/` / `SingleThreadUITests/`). Relevant areas:
the reminder `List` with its card rows, the row's edge swipe actions, the
scroll/refresh configuration shared with the list, the swipe-instruction
prompt and its settings preference, and any gesture handling on iOS/watch.
Describe what exists and how it currently works.

## Questions

1. How does the reminder `List` in `ContentView.swift` construct its card
   rows, and what layout/geometry (insets, padding, widths, list row
   styling) applies to each reminder card? Trace the full view construction
   for the `.case .reminder` list and the `ReminderCardView` row with
   `file:line` references.

2. What SwiftUI swipe / gesture modifiers are used anywhere in the repo, how
   exactly are the `.swipeActions(edge:)` calls in `ContentView.swift`
   configured (buttons, edges, icons, tints), and is there any existing
   custom drag/gesture-recognizer code (e.g. `DragGesture`, thresholds) on
   iOS or watch? Enumerate every swipe/gesture-related call site.

3. How are list scrolling, scroll-bounce, and pull-to-refresh
   (`.refreshable`) configured on the reminder `List` and the other
   `ScrollView`s in `ContentView.swift`? What `.listStyle`,
   `.scrollContentBackground`, `.scrollBounceBehavior`, and `.background`
   modifiers apply, and how do those coexist on the same scrolling surface?

4. How does the swipe-instruction prompt ("Swipe right to complete" /
   "Swipe left to skip") work? Where is it rendered in `ReminderCardView.swift`,
   how is it shown/hidden via the `showSwipePrompt` preference, and how does
   that preference flow from settings bindings/app storage into card
   creation?

5. What unit and UI test patterns exist for the reminder cards, the swipe
   prompt, and the reminder list? Enumerate the relevant test files in
   `SingleThreadTests/` / `SingleThreadUITests/`, which swipe/prompt/scroll
   behaviors they cover, and which testing seams (seeded `--seed` /
   `--ui-testing` launch args, in-memory stores) are used to drive them.

Each question is answered by a separate researcher against the codebase.
Describe what exists. Do not suggest improvements or propose solutions.