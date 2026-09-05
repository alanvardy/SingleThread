# Research Questions

## Context

Focus on the SingleThread iOS/macOS app in `SingleThread/` and `SingleThreadCore/`: the main `ContentView` and its view model, the `ReminderStore` (EventKit-backed reminder loading), the watchOS app's reminder view/view-model (which contains a manual refresh control), and the test targets (`SingleThreadTests` unit tests, `SingleThreadUITests` iOS UI tests, `SingleThreadWatchUITests`, plus the `Makefile`/`scripts` test configuration). The project builds iOS and macOS from a single universal app target with compile-time platform divergence.

## Questions

1. **Platform-conditional UI structure**: How does the single universal target compile platform-specific UI and behavior (`#if os(macOS)` / `#if os(iOS)` / `#if canImport(AppKit)` patterns, entitlements per SDK)? What currently occupies the top-left region of the main `ContentView` window on macOS — which overlay/alignment modifiers and floating buttons already exist, and how are they styled?

2. **Reminder reload flow**: Trace every path that triggers a reminder reload — the `.task` launch loader, each `.refreshable` closure in `ContentView`, the watch app's refresh button, and any other callers. For `ReminderStore.reload(clearSkipped:)`, detail the full step-by-step: EventKit refresh, predicate construction, fetch mechanism (continuation/gate), filtering, state assignment, and post-reload callbacks. How do callers decide the `clearSkipped` argument?

3. **In-flight loading state**: What state do `ReminderStore`, `ContentViewModel`, and `WatchReminderViewModel` track while reminders are loading or refreshing (e.g. `isRefreshing`, minimum display durations)? Where does that state live — store vs view model — how is it set/reset, and how do views surface or react to it?

4. **Watch refresh control precedent**: Where is the watch app's manual refresh button defined, and how is it wired end-to-end — placement/styling, the button's action, disabled logic while refreshing, accessibility identifier/label, and how it relates to the view model's `refresh(clearSkipped:)` method?

5. **Testing patterns for view structure and user flows**: What do existing unit tests assert about view structure (e.g. `contentViewBodyContainsRefreshableModifier`), how do iOS UI tests drive deterministic state via `--seed`/`--ui-testing`/`InMemoryEventStore`, what does the watch UI test for the refresh button assert, how does the accessibility audit work, and what does the macOS test configuration (`make mac-test`, `scripts/test.sh`) actually execute — is there a macOS UI-test target?

6. **Accessibility & localization conventions**: What conventions do interactive buttons in this app follow — accessibility labels, identifiers, traits, SwiftLint-enforced accessibility rules — and how are user-facing strings managed (the `SharedStrings` enum, `Localizable.xcstrings`, watch vs iOS variants)?