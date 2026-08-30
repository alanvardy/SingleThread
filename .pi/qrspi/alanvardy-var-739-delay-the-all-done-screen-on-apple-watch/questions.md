# Research Questions

## Context

The Apple Watch app in `SingleThreadWatch/` shows a single reminder card and
transitions between full-screen states (card, empty states) on user actions.
Completing, skipping, or deleting a reminder mutates shared in-memory state in
`SingleThreadCore` and re-renders the UI, and a transient green overlay
animation runs alongside. Map how these states, mutations, timings, and test
seams currently work.

## Questions

1. **Empty-state presentation.** In the watch app, what distinct full-screen
   states can the reminder UI show (reminder card, "All Done", "No Reminders",
   access/loading states), which view and view properties render each, and
   which `ReminderStore` properties and conditions select between them
   (`allSkipped`, `visibleReminders`, `hasHidden`, `authorizationStatus`,
   `isRefreshing`)? Cite `file:line` for each branch.

2. **Completion / skip / delete mutation flow.** Trace what happens on
   watchOS when the user completes, skips, or deletes a reminder: button →
   view model → `ReminderStore` mutation → WatchConnectivity relay → UI
   re-render. For each path, identify where the in-memory store mutation
   happens (the point that invalidates the observing view) and where in the
   flow the UI switches to an empty state relative to any transient
   animations.

3. **Transient animation and timer mechanics.** How does the `CompletionGlow`
   type work (state, default duration, auto-dismiss task, re-trigger
   semantics), and how is it rendered and animated in the watch view
   (overlay, transition, `.animation` modifier, reduce-motion handling)? What
   other timing/delay utilities and conventions exist in the codebase
   (`MinimumDisplayDuration`, `eventKitSettleDelay`, `Task.sleep` patterns,
   `DispatchQueue.main.asyncAfter`) and where are each used?

4. **Observation and re-render model.** How does the watch UI observe
   store/view-model state and re-render (SwiftUI Observation via
   `@Observable`/`@MainActor`; any Combine or polling)? When a `@Observable`
   property mutates, how does SwiftUI re-evaluate the view body, and how do
   branch switches inside a `ZStack`/`Group` interact with `.animation` and
   `.transition` modifiers on the same hierarchy?

5. **UI-test determinism seams.** What launch-argument seams does the watch
   app expose for UI tests (`--ui-testing`, `--ui-testing-glow`,
   `--ui-testing-glow-disabled`, excluded-list flags), and how do they make
   timing deterministic (e.g. extending the glow duration to 2 s)? How do
   existing watch UI tests wait for and assert transient UI and state
   transitions (`waitForExistence` timeouts, expectations), and what do they
   currently assert about the completion glow and the empty states?

6. **Architecture boundaries and the iOS counterpart.** Which types in the
   completion/empty-state flow live in `SingleThreadCore` (shared across
   iOS/watchOS) versus the watch target, and how does the watch compose them
   (app composition root, view-model ownership, watch-specific state holders
   like `ShowCompletionGlowState`)? For comparison, how does the iOS app
   (`SingleThread/`) implement the same remover→empty-state→glow flow, and
   where does it differ from the watch?