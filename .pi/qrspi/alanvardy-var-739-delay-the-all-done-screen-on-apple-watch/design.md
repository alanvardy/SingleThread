# Design Discussion

## Current State

The watchOS app shows a single reminder card with Complete / Skip / Delete
actions. When the user completes the last visible reminder, two things happen
in the same MainActor turn:

1. `ReminderStore.reminders.removeAll` mutates synchronously
   (`ReminderStore.swift:148`), causing SwiftUI Observation to invalidate
   `WatchReminderView.body`.
2. `CompletionGlow.trigger()` fires (`WatchReminderViewModel.swift:45`),
   starting a 0.50 s auto-dismiss timer.

Because the store mutation and glow trigger happen in the same synchronous
turn, the empty-state branch swap (`allSkipped` or `else` → No Reminders,
`WatchReminderView.swift:77-82`) and the green glow overlay render in the
same frame. The user sees the "All Done" or "No Reminders" text appear
**through** the fading green glow — the card vanishes instantly, undermining
the satisfying "task accomplished" moment.

On iOS this isn't a problem: the EventKit save + `eventKitSettleDelay` +
reload round-trip (`ReminderStore.swift:152-168`) inserts a natural delay
between the glow trigger and the empty state. The watch's in-memory mutation
has no such gap.

The completion flow: button tap → `completeCurrentReminder()` async call
(`WatchReminderView.swift:104`) → store mutation → glow trigger → body
re-evaluation. No suspension points exist on the watch path between mutation
and glow.

## Desired End State

After completing the last remaining reminder on watchOS:

1. The reminder **card stays visible** for the full glow duration plus a
   short buffer (~0.5 s after the glow fades).
2. The green glow overlay animates in and out over the still-visible card.
3. After the delay, the view transitions smoothly to the appropriate empty
   state (All Done / No Reminders).

**Verification**: under `--ui-testing-glow` (2 s glow + 0.5 s buffer = 2.5 s
total delay), a UI test can:
- Assert the card text is still visible immediately after tapping Complete
  (it should NOT disappear in < 1 s).
- Assert the glow overlay appears (existing assertion preserved).
- Assert the empty state appears after the delay elapses.

## Patterns to Follow

| Pattern | Source | Usage |
|---|---|---|
| `@Observable` state flag gating a content branch | `WatchReminderViewModel.isRefreshing` (`:38`) → `if viewModel.isRefreshing { ProgressView() }` (`WatchReminderView.swift:85-88`) | New flag suppresses empty-state branch; the existing card branch renders instead |
| `Task.sleep` for transient delays on MainActor | `CompletionGlow.trigger()` dismiss task (`CompletionGlow.swift:38`); `WatchReminderViewModel.refresh()` minimum display (`WatchReminderViewModel.swift:63`); `ReminderStore.eventKitSettleDelay` (`ReminderStore.swift:364`) | Delay task sleeps for `glow.duration + 0.5`, then clears the flag |
| Test seam: injectable `duration` on `CompletionGlow` | `WatchAppViewModel` glow seam extends duration to 2.0 s (`WatchAppViewModel.swift:48`) | New buffer constant also needs to be test-configurable (either a separate property or a fixed computation off `duration`) |
| Unit tests: `@MainActor @Suite(.serialized)` with injected store | `CompletionGlowTests.swift:13-14`; `CompletionGlowViewModelTests.swift:47-48` | New view-model tests follow the same pattern |
| UI tests: `waitForExistence(timeout:)` assertions, no sleeps | `SingleThreadWatchUITestsFlows.swift:73-83` (complete → No Reminders) | New UI test extends the complete-flow test: assert card persists briefly, then assert empty state appears |
| View-model owns presentation state, not the view | `WatchReminderViewModel` holds `isRefreshing`, `isShowingRefreshConfirmation`, `completionGlow` | New flag lives in the view model, not as `@State` in the view |

**Patterns to avoid**:

- **Do NOT add a delay to `ReminderStore`** — the store is the data layer;
  presentation timing belongs in the view model. iOS doesn't need this delay
  (it has a natural one from EventKit), and the `#if os(watchOS)` branches
  in `ReminderStore` (`:147-151`, `:183-185`) already keep platform
  differences minimal.
- **Do NOT use `DispatchQueue.main.asyncAfter`** — the existing convention
  is `Task.sleep` (`CompletionGlow.swift:38`, `WatchReminderViewModel.swift:63`,
  `ReminderStore.swift:236`). The lone `asyncAfter` in the watch target
  (`WatchAppViewModel.swift:208-212`) is a UI-test-only context-delivery
  seam, not a production pattern.
- **Do NOT add a new type in `SingleThreadCore`** — the change is purely a
  watchOS presentation concern. The glow itself remains shared; only the
  post-glow card-hold behavior is watch-specific.

## Design Decisions

1. **Delay location: view-model state flag** — A new `Bool` property
   (e.g. `isShowingCompletionTransition`) on `WatchReminderViewModel`
   gates the empty-state branch. When `true`, the card branch continues
   rendering even though the store says the reminders array is empty.
   Mirrors `isRefreshing` (`WatchReminderViewModel.swift:38`).

2. **What the user sees: completed card + glow** — During the delay, the
   reminder card remains on screen with the green glow overlay fading over
   it. The card's action buttons (Complete, Skip) remain but tapping them is
   a no-op (the store has no visible reminder to act on — the card is a
   ghost from the view model's perspective). After the delay, the card
   disappears and the empty state appears.

3. **Delay formula: `completionGlow.duration + 0.5 s`** — The flag is set
   synchronously in `completeCurrentReminder()`, then a `Task.sleep` of
   `glow.duration + 0.5` clears it. This gives 0.50 + 0.50 = 1.0 s in
   production and 2.0 + 0.50 = 2.5 s in UI tests, matching the 1–2 s spec
   while keeping the test seam deterministic. The 0.5 s buffer constant
   lives as a `private static let` on the view model.

4. **Scope: complete path only** — Skip already has a natural ~200 ms
   deferred mutation (`ReminderStore.swift:235-238`). Delete is destructive
   and shouldn't linger. Neither path triggers the glow. Only
   `completeCurrentReminder()` sets the new transition flag.

5. **Flag clearing: after the sleep, check the store** — When the delay
   ends, the view model checks `store.visibleReminders.isEmpty` before
   clearing the flag. If a refresh or sync repopulated reminders during the
   delay, the flag stays set (card stays) and a new card appears instead of
   flashing empty-then-card. Edge case: rare, but cheap to guard against.

6. **Accessibility: no change** — During the delay, the card's accessibility
   elements remain present and the glow overlay stays `accessibilityHidden`
   (production) or visible (UI test seam). The Complete/Skip buttons are
   still in the tree but point to no-op actions — VoiceOver users won't get
   confused because the button labels haven't changed. The empty-state
   labels appear after the delay as before.

## What We're NOT Doing

- **Not changing the iOS flow** — iOS has a natural delay from EventKit
  round-trips. The watch-only presentation concern stays in the watch-only
  view model.
- **Not changing skip or delete behavior** — those paths are unchanged.
- **Not adding transitions/animations to the branch swap** — the empty state
  still appears without animation (same as today). Only the glow overlay
  animates. The delay makes the swap happen after the glow, which is the
  desired effect.
- **Not extracting a shared "post-completion delay" type** — this is a
  single-purpose flag on one view model, not a reusable abstraction.
- **Not changing `CompletionGlow` or `ReminderStore`** — no shared-code
  changes. The implementation touches only `WatchReminderViewModel` (state +
  logic), `WatchReminderView` (branch gating), and tests.

## Open Risks

1. **Grey-period button taps**: During the delay, the card's Complete/Skip
   buttons remain visible. The store has no visible reminder, so those
   actions are no-ops — but a rapid double-tap on Complete could re-enter
   `completeCurrentReminder()` while the flag is already set. Mitigation:
   guard the method with the flag (`if isShowingCompletionTransition { return }`)
   so the second trigger is ignored.

2. **Refresh arriving mid-delay**: A WatchConnectivity push or a completion
   relay from the phone could repopulate `reminders` during the delay. The
   design decision #5 (check store before clearing) handles this, but the UX
   of "card changes mid-glow" should be tested — it's benign (new card
   appears, delay extends until that card's fate is decided).

3. **UI test timing drift**: The 2.5 s delay under `--ui-testing-glow` is
   long enough for reliable `waitForExistence` assertions but borderline for
   CI time budgets. The existing watch UI test suite runs quickly; adding a
   few seconds per complete-flow test is acceptable but should be watched.