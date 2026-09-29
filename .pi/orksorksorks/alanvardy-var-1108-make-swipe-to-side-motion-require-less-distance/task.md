# Task

Make the iOS reminder card's swipe-to-side gesture require less travel
distance. Today the reminder row in `ContentView.swift` exposes Complete and
Skip via SwiftUI's built-in `.swipeActions(edge: .leading)` /
`.swipeActions(edge: .trailing)` modifiers; triggering the edge action
requires dragging the row most of the way across the screen (compounded by
the row's ~40pt horizontal insets), which feels like too much travel. The
goal is to cut the required swipe distance roughly in half so the gesture
feels easier, without regressing the swipe-reveal affordance, the "Swipe
right to complete / Swipe left to skip" prompt, List scrolling, or
pull-to-refresh.

This is a LARGE task with design sign-off: SwiftUI's system `.swipeActions`
exposes no public API to configure its full-swipe trigger threshold, and
there is no existing drag-gesture pattern in the codebase to copy (the watch
uses a tap; the other lists are plain). A replacement interaction — likely a
custom `DragGesture`-driven drag-to-trigger with a lowered threshold and a
snap-back/edge-reveal behavior — must be designed, with real product trade-offs
(threshold value/feel, whether to keep or drop `.swipeActions`, how the prompt
and labels map onto the new gesture, gesture vs. `List` scroll/`.refreshable`
coexistence, iOS-only scoping). The approach needs a design decision and human
sign-off before implementation.