# Implementation Summary

All three phases of the "make swipe-to-side motion require less distance" ticket
are implemented, committed (one commit per phase), and pushed to
`origin/alanvardy-var-1108-make-swipe-to-side-motion-require-less-distance`.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `f95c493` | Walking skeleton — half-distance drag fires Complete/Skip end to end |
| 2     | `83ff078` | Reveal affordance — card follows finger behind a tinted hint panel |
| 3     | `fe5f240` | Hardening & proof — accessibility parity, audits, the one UI gesture test |

Also on the branch (bootstrap housekeeping): `6ba6a54` removed the `DELETEME`
bootstrap marker that the branch was bootstrapped with (required before merge).

## Automated Checks

- [x] `make format` then `make lint` clean (SwiftFormat + SwiftLint `--strict`) — Phases 1–3
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` green (Phase 1)
- [x] `make build` succeeds (Phases 1–2)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` green (Phases 1 and 3)
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green (Phase 2)
- [x] `scripts/test-one.sh SingleThreadTests/SwipePromptTests` green (Phase 2)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testHalfDistanceSwipeCompletesReminder` green (Phase 3)
- [x] `make ui-test` green (full iOS UI suite + accessibility audit; all 4 cases incl. the a11y-audit smoke) — Phase 3
- [x] `make test` green (macOS-native `SingleThreadTests`, incl. Phases 1–2 suites; the three documented pre-existing local `EntitlementStoreTests` failures were treated as pre-existing per `conventions.md`) — Phase 3
- [x] `make periphery` clean — Phase 3

Deferred (belongs to the review step, per the implement/review protocol):
- [ ] Full gate via the `run-gate` skill (`./scripts/test.sh`) once after all three phases commit (plan item 6) — never `nohup`’d ad hoc.

## Manual Verification Items (from the plan)

- [ ] **Phase 1** — On the iOS sim (`SIM=platform=iOS Simulator,id=6F5F8C04-4CC2-4B11-8171-EC9D4F4DCAD7`): drag the card ~72pt right → Complete fires once; drag left → Skip fires once; drag ~30pt → nothing, card returns to centre.
- [ ] **Phase 1** — Vertical scroll of the card area still scrolls; pull-to-refresh still triggers `reload()`; Dismiss on the prompt and the nudge banner still tap.
- [ ] **Phase 2** — Partial right drag on the sim: tinted Complete panel is revealed behind the card and brightens as it approaches 72pt; release under threshold snaps back with no action and no leftover panel.
- [ ] **Phase 2** — Partial left drag shows the Skip panel; release past 72pt fires Skip and the card animates back to centre.
- [ ] **Phase 2** — No stuck-offset card after either release.
- [ ] **Phase 3** — On the sim: VoiceOver (or Accessibility Inspector) exposes "Complete" and "Skip" as actions on the card.
- [ ] **Phase 3** — Scroll the list and pull-to-refresh still work; the prompt + Dismiss and nudge banner are unchanged.
- [ ] **Phase 3** — On-device (or sim) feel check: a ~72pt drag is noticeably easier than the old full-swipe; if the feel is wrong, `SwipeGesture.releaseDistance` is the single constant to tune (unit + UI test thresholds derive from it).

## Notable deviations / findings (for review)

1. **The plan's Phase 3 UI-test seam was wrong; this blocked Phase 3.** The plan
   chose plain `--ui-testing` for `testHalfDistanceSwipeCompletesReminder`,
   reasoning it was "what `testLaunchAndRenderSmoke` proves". That seam only
   renders the reminder — **a complete never removes it from the visible list
   there** (verified: even tapping `completeButton` left "Buy groceries" present;
   `XCTWaiter rawValue 2`). The test therefore failed regardless of the drag
   mechanism. Fix: drive the write flow through the AGENTS.md-documented
   `--seed '<json>'` seam (`InMemoryEventStore`) + `--ui-testing-noop-settle`
   for deterministic/fast settle. Then the reminder renders *and* a completion
   removes it, and the drag passes end to end (verified green via harness and in
   the full `make ui-test` run).
   - **Consequence:** the seed JSON is passed as a single launch argv, and the
     runner splits argv on spaces — so the seeded title must be a single word.
     The test seeds an entitled "Milk" reminder (priority 5) instead of
     "Buy groceries". This does not change what the test proves (a ~90pt drag
     completes the reminder).
2. **Drag driving uses explicit velocity + brief release hold**
   (`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`) rather
   than the plan's bare `press(forDuration:thenDragTo:)`. Apple's XCUITest
   guidance recommends a controlled velocity for a deliberate drag so a `List`
   doesn't fling-scroll and `DragGesture` reads the full translation. This was
   kept as a robustness improvement; the plan's plain drag was never the cause
   of the failure (the seam was).
3. **Two pre-existing Phase 1/2 test-file defects were fixed in the Phase 3
   commit** (both behaviour-preserving, both required to keep the tree green):
   - `SingleThreadTests/SwipeGestureDecisionTests.swift`: removed an unused
     `@testable import SingleThread` (Periphery `--strict` failed on it).
   - `SingleThreadTests/SwipeToActModifierTests.swift`: one-line SwiftFormat
     canonicalization to trailing-closure form (SwiftLint `--strict` failed on
     it). Reviewed-and-approved by the main agent via supervisor before landing.
   - These should be noted as a small Phase 1/2 hygiene debt: each phase's own
     verification should have caught them, but they were only surfaced when the
     Phase 3 gate ran the full checks.
4. **Phase 2 test adaptation (worker-reported):** `SwipeToActModifierTests.swift`
   could not call `ViewModifier.body(content:)` directly (the runtime `Content`
   sample type has no public constructor), so the worker reflects the modifier
   applied over a SwiftUI-composed host instead; panel label/CardPlate rendering
   is asserted directly via `SwipeRevealPanel.body`. Tests are green.
5. **Simulator flakiness note:** the dedicated sim (`.simulator_id`
   `6F5F8C04-…`) intermittently hit `RequestDenied` on the `xctrunner` launch
   (cold-start), unrelated to the change; recovering by booting the sim and
   re-running on the warm build cleared it. This cost two phase-subagent
   timeouts (Phase 1 and Phase 3).
6. **`swipePrompt` guide under `--seed`:** the first-launch swipe guide
   (`showSwipePrompt` default true) is not suppressed under `--seed` (only the
   `--ui-testing` path suppresses it). It did not block the drag or the buttons
   in the UI tests, so no change was needed; worth re-checking in the manual
   on-device feel pass.