# Design Discussion

## Current State

The iOS reminder card is a **single-row** `List` under the `.reminder` arm of
`reminderList` (`ContentView.swift:437-517`); only
`viewModel.store.visibleReminders.first` is rendered (`ContentView.swift:443`).
The row is one `ReminderCardView` (`ContentView.swift:446-457`) carrying
`.padding(.horizontal, 40)` / `.padding(.vertical, 12)`, centered in a
full-width row (`.frame(maxWidth: .infinity, alignment: .center)`), and sized
to the full content height (`ContentView.swift:459-466`). The card plate is
capped at `min(340, viewportWidth * 0.6)` by `CardWidth.maxContentWidth`
(`CardWidth.swift:11-13`).

Today Complete and Skip are exposed by stock SwiftUI `.swipeActions`:

- leading (complete) `ContentView.swift:488-494` — `checkmark.circle.fill`,
  `.tint(.green)`, calls `viewModel.completeCurrentReminder()`;
- trailing (skip) `ContentView.swift:496-503` — `circle.slash`,
  `.tint(.orange)`, calls `viewModel.skipCurrentReminder()`.

Research established that **`.swipeActions` gives no public API to lower its
full-swipe trigger** (task premise) and that **no custom drag/gesture code
exists anywhere** in iOS, Core, or Watch (research Q2): the watch uses
`.onTapGesture` (`WatchReminderView.swift:245`) and the other lists are plain.
So there is no in-repo gesture pattern to copy.

The system gesture competes with `List` scrolling and pull-to-refresh
(`.refreshable`, `ContentView.swift:514-516`); the swipe hint prompt is
visual-only, gated by `@AppStorage("showSwipePrompt")` and routed through
`swipePromptBinding` (`ContentView.swift:380-384`), rendered in
`ReminderCardView.swift:43-53,177-224`. No test exercises an actual swipe: all
swipe coverage is view-reflection unit tests (`SwipePromptTests.swift`) plus
the `--ui-testing`/`--seed` launch-arg seams.

## Desired End State

The card triggers Complete (drag right) / Skip (drag left) after releasing
past **~72pt** of horizontal travel — roughly **half** the current full-swipe
distance — while:

1. the card follows the finger and reveals a tinted Complete/Skip hint panel
   behind it, intensifying as the threshold nears (the swipe-reveal affordance
   is preserved, not regressed);
2. release past threshold fires the action once, then the card snaps back
   (settling to zero offset) — no stuck-open state;
3. release before threshold snaps the card back with no action;
4. vertical-dominant drags never move the card, so `List` scrolling and
   pull-to-refresh are untouched;
5. the "Swipe right to complete / Swipe left to skip" prompt and its Dismiss
   flow are unchanged;
6. all of the above is plain SwiftUI, cross-platform-safe, and unit-testable
   on the macOS host.

Verification: a pure threshold-decision unit test (right past 72pt → complete,
left past 72pt → skip, under-threshold → none, vertical-dominant → none), a
view-reflection test that the hint panel renders per direction, and one
coordinate-drag UI test proving a **half-distance** drag triggers the action.

## Patterns to Follow

- **Reuse plate colors, don't invent new ones** — `CardPlate.skipHintColor` /
  `completeHintColor` (`CardPlate.swift:32,39`) and
  `CardPlate.plateFill(for:)` (`:23`) are the established palette for the hint
  prompt (`ReminderCardView.swift:191,197`). The new behind-card panel should
  use the same colors so the reveal reads as the same vocabulary.
- **iOS-only scoping via a binding, not scattered guards** — the existing
  pattern is `swipePromptBinding` returning `$showSwipePrompt` on iOS and
  `.constant(false)` elsewhere (`ContentView.swift:380-384`). Follow this for
  anything platform-specific rather than sprinkling `#if` in the view body.
- **View-reflection unit tests** — the repo tests view behavior by
  `String(describing: view.body)` (`SwipePromptTests.swift:12-24,58-63`;
  `ReminderDisplayRowTests.swift:11,17,23,29`). Card-level changes get the
  same treatment.
- **Swift Testing for units, XCTest for UI**; unit-test names must not start
  with `test`/`testing` (SwiftFormat strips them). UI tests keep `test…`.
- **Testing seams** — `--ui-testing` + `--seed '<json>'` against
  `InMemoryEventStore` is the sanctioned way to drive deterministic UI flows
  (`SingleThreadUITests.swift:38,82,154`; `UITestingSeed.swift:186`); reuse it.
- **Threshold as a named constant** — mirror the `defaultThreshold = 6`
  convention in `SkipCountStore.swift:5-18`: a `static let` on a small type,
  not a magic literal in the view.
- **Do NOT follow**: `.swipeActions` itself. Also do **not** copy
  `.contextMenu`'s `#if os(iOS)`-in-body style (`ContentView.swift:467-486`) if
  the gesture can stay cross-platform — the macOS-host unit target builds this
  view, and guards there break reflection-test coverage.

## Design Decisions

1. **Replace `.swipeActions` with a custom row `DragGesture`** — Option A. Full
   control over trigger distance; no competing gesture systems. The card
   translates, a hint panel reveals behind it, and release decides. Removing
   the two `.swipeActions` blocks (`ContentView.swift:488-503`) removes the
   un-tunable system threshold entirely.
2. **Fixed 72pt release-to-fire threshold** — Option A. Half of a ~144pt full
   swipe, direction-agnostic (positive x = complete, negative = skip),
   independent of viewport so it is trivially unit-testable. Drags that are
   vertical-dominant (|dy| > |dx|) are ignored so the `List` scroll keeps
   winning. `DragGesture(minimumDistance:)` with a small minimum prevents taps
   from being eaten.
3. **Translate the card + reveal a tinted hint panel** — Option A. Preserves
   the reveal affordance; opacity/color intensity scales with
   `min(|dx| / threshold, 1)` so the "how close am I" feedback survives. Panel
   labels reuse the existing Complete/Skip strings and `SharedStrings` action
   names (`Label` semantics) so accessibility labels stay consistent with
   `bottomBar`.
4. **Unit-test the decision, UI-test the gesture** — Option A. The
   direction/threshold/dominance logic is extracted into a pure helper, so the
   core rule is unit-tested without a gesture runtime; the coordinate-drag UI
   test is the single justified UI test because the bug is a *distance-to-
   trigger* feel regression that only manifests at the gesture layer. Say so in
   the PR.
5. **Plain SwiftUI, no haptics, no `#if os(iOS)` in the gesture path** —
   Option A. `DragGesture` + animation are cross-platform, keeping the macOS
   unit-test host compiling and the view reflection-testable. Haptics are out
   of scope rather than hidden behind a guard.
6. **Fire-on-release, then reset to zero offset** — release semantics avoid
   accidental mid-drag triggers and guarantee no stuck-open row for the
   single-row list. `withAnimation` on the reset matches the rest of the
   view's motion.

## What We're NOT Doing

- **Not** keeping any `.swipeActions` code path, and not adding a second
  simultaneous gesture (Q1 Option B).
- **Not** adding `UIImpactFeedbackGenerator` / haptics (Q5 Option B).
- **Not** touching `ReminderCardView`'s prompt (`:177-224`), its Dismiss
  button, the `showSwipePrompt` `@AppStorage` key, or the Settings toggle
  (`InterfaceSettingsView.swift:131-142`).
- **Not** changing `bottomBar`'s existing Complete/Skip buttons, nor the
  `.refreshable` / `.scrollContentBackground` / `.listStyle` configuration
  (`ContentView.swift:505-516`).
- **Not** altering `CardWidth` (`CardWidth.swift`) or the 40pt row insets —
  the fix is threshold-driven, not geometry-driven.
- **Not** adding a new test target (would need pbxproj/scheme/test.sh/CI
  wiring); new test files sit in the existing `SingleThreadTests` /
  `SingleThreadUITests` targets.
- **Not** changing any deployment-target floors.

## Open Risks

- **Gesture vs. `List` scroll coexistence is not determinable from source**
  (research Q3 Open Areas). A `DragGesture` on a `List` row can be intercepted
  by the scroll view. Mitigation: `simultaneousGesture` + explicit
  vertical-dominance rejection, verified by the UI test's scroll and
  pull-to-refresh checks. If the row gesture still swallows scrolls, the
  fallback is attaching the gesture to the card content via `.contentShape`
  and a `minimumDistance` that scroll can out-compete — a known-risky area to
  validate first.
- **`predictedEndTranslation`-free release semantics** can feel less
  flick-responsive than the system; 72pt is a feel hypothesis that the UI/manual
  on-device check must confirm, and it is a one-constant change if wrong.
- **`bottomBar` contents are unverified** (research Open Areas). The
  `testLaunchAndRenderSmoke` complete/skip assertions (`SingleThreadUITests.swift:43-67`)
  most likely resolve to `bottomBar`, but if they resolve to swipe-action
  buttons, removing `.swipeActions` breaks that test — confirm before landing.
- **Accessibility**: `.swipeActions` buttons are reachable by VoiceOver only
  after reveal; the replacement must expose equivalent accessibility actions
  (labels from `SharedStrings.completeAction` / `skipAction`) so no action is
  lost. Rotation/`.dynamicType` audit is the guard.
- **Reflection tests on the macOS host** may render the gesture view
  differently than iOS; keep the threshold logic in a pure helper so the
  critical rule is host-tested independently of gesture runtime.