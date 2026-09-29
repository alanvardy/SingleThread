# Done

- **Branch / head SHA**: `alanvardy-var-1108-make-swipe-to-side-motion-require-less-distance` @ `7a783602` (post-review fixes). Full CI gate passed on `cae21e38`.
- **Mechanical checks**:
  - `make format` — 0/229 files changed.
  - `make lint` (SwiftFormat + SwiftLint `--strict`) — 0 violations.
  - Full CI gate `./scripts/test.sh` — **PASS** on `cae21e38` (`✅ All CI checks passed.`, exit 0): iOS/watch builds, iOS UI, watch UI, watch unit, macOS unit suites all green; Periphery `No unused code detected`; compiler-warning allowlist untouched; no Busy/RequestDenied restarts. Run in a managed worktree (torn down after the verdict).
  - Post-review commit `7a783602` validated with targeted suites: `SwipeGestureDecisionTests` (10 cases), `SwipeToActModifierTests` (3 cases), `SingleThreadUITests/testOverThresholdSwipeCompletesReminder` (1 case) — all green. The full gate was **not** re-run on `7a783602` (doc/test-name + presentation refactor only); CI is authoritative for the final commit.
- **Review outcome**: One fresh-context reviewer pass; **no blockers**. Fixes applied:
  1. UI test renamed `testHalfDistanceSwipeCompletesReminder` → `testOverThresholdSwipeCompletesReminder`; doc/comment corrected (the drag is *past* the 72pt threshold, not half of it); drag widened 90pt → 110pt for flake margin.
  2. `SwipeRevealPanel`'s three parallel switches collapsed into a nested `Presentation` struct (one source for title/icon/tint) — avoids the strict `large_tuple` rule.
  3. `SwipeGesture.revealedOutcome(forOffset:)` extracted into `SingleThreadCore` and covered by 3 new unit tests.
  4. `progress` denominator floored at 1 (`max(threshold, 1)`) so a zero threshold cannot divide by zero.
  Declined / deferred (with reason): defensive `dragOffset` reset if `onEnded` is ever skipped (no clean SwiftUI cancellation hook; no live path identified under `simultaneousGesture`); gating `onChanged` offsets on horizontal dominance (deferred to the manual on-device feel pass); tightening the reflection-based modifier tests.
- **Remaining manual items**: the plan's manual verification items are still unrun —
  - On-sim feel pass: drag ~72pt right → Complete fires once; drag left → Skip fires once; ~30pt → nothing, card returns to centre; tinted Complete/Skip reveal panel brightens toward the threshold; vertical scroll and pull-to-refresh still work; prompt Dismiss and nudge banner still tap.
  - VoiceOver (or Accessibility Inspector): "Complete" and "Skip" are exposed as actions on the card.
  - If the trigger distance feels wrong, `SwipeGesture.releaseDistance` (72) is the single constant to tune (unit and UI test thresholds derive from it).
- **Housekeeping**: `DELETEME` bootstrap marker removed (`6ba6a54`); ticket artifacts committed; gate worktree removed.