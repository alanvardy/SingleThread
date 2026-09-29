# Structure Outline

## Approach

Replace the untunable `.swipeActions` on the single reminder row with a custom
`DragGesture` that fires Complete (drag right) / Skip (drag left) on release past
a fixed **72pt** threshold, ignoring vertical-dominant drags. Extract the
direction/threshold/dominance rule into a pure, macOS-host-testable helper
(contract for every slice), then layer the reveal affordance and accessibility
parity on top. Plain SwiftUI, no `#if os(iOS)` in the gesture path, no geometry
change.

## Phase 1: Walking skeleton — half-distance drag fires Complete/Skip end to end

The user can drag the reminder card ~72pt left/right and release to fire Skip /
Complete exactly once; under-threshold and vertical-dominant drags do nothing.
The `.swipeActions` blocks are gone. This front-loads the riskiest unknown
(Q3: custom row `DragGesture` coexisting with `List` scroll / `.refreshable`).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift` (new),
`SingleThread/ContentView.swift` (row only), `SingleThreadTests/SwipeGestureDecisionTests.swift` (new)

**Key changes**:
- `enum SwipeGestureOutcome: Equatable { case complete, skip, none }` — new
- `enum SwipeGesture { static let releaseDistance: CGFloat = 72; static func outcome(for translation: CGSize, threshold: CGFloat = releaseDistance) -> SwipeGestureOutcome }` — new. Rule: `abs(dy) > abs(dx)` → `.none`; `dx >= threshold` → `.complete`; `dx <= -threshold` → `.skip`; else `.none`.
- `ContentView.reminderList` `.reminder` arm — delete both `.swipeActions` blocks; add `@State private var dragOffset: CGFloat` + `DragGesture(minimumDistance:)` on the card row (`.simultaneousGesture` so `List` scroll can still win), `onEnded` → `SwipeGesture.outcome(for:)` → `viewModel.completeCurrentReminder()` / `skipCurrentReminder()`, then reset offset.
- Keep an equivalent `.accessibilityAction(named:)` for Complete/Skip so no action is lost with `.swipeActions` removed.

**Contract**: `SwipeGesture.outcome(for:threshold:) -> SwipeGestureOutcome` and
`SwipeGesture.releaseDistance` — later slices consume only this, never the row's
`@State`.

**Tests**: `SwipeGestureDecisionTests` — right past 72pt → `.complete`, left past → `.skip`, under-threshold → `.none`, vertical-dominant → `.none`, exactly-at-threshold boundary, custom `threshold:` override.
**Verify**: `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` green; existing `SingleThreadUITests/testLaunchAndRenderSmoke` still green (confirms its Complete/Skip assertions resolve to `bottomBar`, not the removed `.swipeActions`); manual on-device drag confirms scroll/pull-to-refresh still work.

---

## Phase 2: Reveal affordance — card follows finger behind a tinted hint panel

While dragging, the card translates with the finger, a tinted Complete/Skip panel
reveals behind it and intensifies toward the threshold; release always animates
the card back to zero (no stuck-open state). Extract the gesture into one
reusable modifier.

**Files**: `SingleThread/SwipeToActModifier.swift` (new),
`SingleThread/ContentView.swift` (apply modifier),
`SingleThreadTests/SwipeToActModifierTests.swift` (new)

**Key changes**:
- `struct SwipeToActModifier: ViewModifier { init(threshold: CGFloat = SwipeGesture.releaseDistance, onOutcome: @escaping (SwipeGestureOutcome) -> Void) }` — new; owns drag state, snap-back `withAnimation`, and the behind-card panel.
- `struct SwipeRevealPanel: View { init(outcome: SwipeGestureOutcome, progress: CGFloat) }` — new; `progress = min(abs(dx) / threshold, 1)`; colors from `CardPlate.completeHintColor/skipHintColor` + `plateFill(for:)`, labels from `SharedStrings.completeAction/skipAction`.
- `extension View { func swipeToAct(threshold:onOutcome:) -> some View }` — new.
- `ContentView` row: replace Phase-1 inline gesture with `.swipeToAct(onOutcome:)`.

**Contract**: `.swipeToAct(threshold:onOutcome:)` — Phase 3 adds accessibility
parity and test hooks on/around this modifier, not on the row body.

**Tests**: `SwipeToActModifierTests` (reflection via `String(describing: body)`) — panel renders the Complete label/hint for `.complete` and Skip for `.skip`; `.none` renders no panel; `CardPlateModifier` present. Existing `SwipePromptTests` still green (prompt markup untouched).
**Verify**: `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green; `make build`; manual: partial drag shows the panel, release under threshold snaps back with no action.

---

## Phase 3: Hardening & proof — accessibility parity, audits, the one UI gesture test

VoiceOver exposes Complete and Skip as named actions on the card; the
accessibility audit (hit region / dynamic type) passes; one coordinate-drag UI
test proves a **half-distance** drag triggers the action end to end.

**Files**: `SingleThread/SwipeToActModifier.swift`, `SingleThreadUITests/SingleThreadUITests.swift`

**Key changes**:
- `.accessibilityAction(named: SharedStrings.completeAction/skipAction)` + `.accessibilityIdentifier("reminderCard")` for the drag target; confirm labels stay consistent with `bottomBar`.
- `func testHalfDistanceSwipeCompletesReminder()` — seed one reminder via `--ui-testing` + `--seed`, `press(forDuration:thenDragTo:)` from card centre to ~72pt right, assert the next card / completion state.
- Localisation check: reuse existing "Complete"/"Skip" keys (no new `.xcstrings` entries); add any new key to the localization test fixtures if one is introduced.

**Contract**: final behavior — no new public type.

**Tests**: the new UI test + `testAccessibilityAudit()` on the iOS sim; `SwipeGestureDecisionTests` / `SwipeToActModifierTests` stay green.
**Verify**: `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testHalfDistanceSwipeCompletesReminder` green (pinned by `.simulator_id`); `make ui-test`; manual on-device: scroll + pull-to-refresh unaffected, prompt + Dismiss unchanged. Full gate runs once via `run-gate`.

---

## Testing Checkpoints

- **After Phase 1**: `SwipeGestureDecisionTests` + `testLaunchAndRenderSmoke` green → proceed.
- **After Phase 2**: `SwipeToActModifierTests` + `SwipePromptTests` green, `make build` → proceed.
- **After Phase 3**: new UI test + a11y audit green, scroll/refresh manual check done → full gate.
- Do not advance past a red slice; no slice depends on another's internals (all cross-slice integration goes through `SwipeGesture.outcome` and `.swipeToAct`).