# Task

Make the iOS reminder card's swipe-to-side gesture require less travel
distance. Today the reminder row in `ContentView.swift` exposes Complete and
Skip via the built-in SwiftUI `.swipeActions(edge: .leading)` /
`.swipeActions(edge: .trailing)` modifiers; triggering the edge action
(especially the system "full swipe to the side") demands dragging the row most
of the way across the screen (compounded by the row's ~40pt horizontal
insets). The goal is to cut the required swipe distance roughly in half so the
gesture feels easier, without regressing the swipe-reveal affordance, the
"Swipe right to complete / Swipe left to skip" prompt, List scrolling, or
pull-to-refresh.

## Why LARGE

UNKNOWNS + DESIGN_SIGN-OFF: SwiftUI's system `.swipeActions` exposes no public
API to configure its full-swipe trigger threshold, so the task cannot be done
by tweaking a constant — it requires designing a replacement interaction (a
custom `DragGesture`-driven drag-to-trigger with a lowered threshold, likely
with a snap-back / edge-reveal behavior), and there is **no existing
drag-gesture pattern in the codebase** to follow (the watch uses a tap and the
remaining lists are plain). Several viable implementations exist with real
product trade-offs (threshold value/feel, whether to keep the system
reveal-vs. `swipeActions`, how the existing swipe-instruction prompt and
labels map onto the new gesture, gesture-vs-`List`-scroll and `.refreshable`
coexistence, iOS-only scoping), so the approach needs a design decision and
human sign-off before implementation. This is the core primary user
interaction, so gesture/accessibility regressions are hard to contain and need
deliberate testing (unit + UI gesture behavior).