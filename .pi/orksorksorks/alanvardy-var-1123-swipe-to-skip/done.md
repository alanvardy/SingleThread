# Done

- **Branch / head SHA**: `alanvardy-var-1123-swipe-to-skip` @ `5e6d57ab`
  (pushed to `origin/alanvardy-var-1123-swipe-to-skip`).
- **Mechanical checks**:
  - `make format` idempotent (tree stayed clean), `make lint` → `swiftlint
    --strict`, 0 violations.
  - `make build` (iOS) and `make mac-build` both `** BUILD SUCCEEDED **`.
  - Targeted suites green: `SwipeGestureDecisionTests` (10), `SwipeToActModifierTests`
    (6), `AppLanguageTests` (8), `testOverThresholdSwipeOpensActionMenu` (1),
    `testOverThresholdSwipeCompletesReminder` (1).
  - **Full CI gate PASS** (`./scripts/test.sh`, run once via the `run-gate`
    skill at tip `5e6d57ab`): allowlisted compiler-warning check clean,
    Periphery "No unused code detected", build SUCCEEDED, iOS UI tests
    SUCCEEDED, watch UI tests SUCCEEDED, macOS unit tests SUCCEEDED.
    Gate log: `/tmp/gate-var-1123.log`; verdict: `gate.md`.
  - Gate lane torn down (`worktree_remove` + `git branch -D
    pi-subagents/gate-bc7f7a8-ef16-s0-t0` after a 0-unique-commit reachability
    check).
- **Review outcome**: one bounded fresh-context reviewer pass plus a parent
  scan. **No blockers.** Reviewer "OK with notes" — rename exhaustive, iOS
  state/dialog wiring and the 6-locale `moreAction` key correct.
  - **Applied fix 1(B)** (reviewer P1, confirmed): a left swipe on macOS
    revealed the "More" panel but fell through to `skipCurrentReminder()`.
    Moved `isShowingActionMenu` / `actionMenuReminder` out of `#if os(iOS)`,
    made `presentActionMenu()` / `actionMenuDialogButtons` cross-platform,
    changed the `.more` dispatch to `presentActionMenu()` on both platforms,
    and widened the `.confirmationDialog` host to `#if os(iOS) || os(macOS)`.
  - **Applied fix 2**: iOS bottom-bar accessibility label is now conditional
    (`showActionMenu ? moreAction : skipReminderAccessibility`); previously it
    announced "More" even when the toggle-off path performed a direct skip.
  - **Applied fix 3**: stale "Skip" → "More" doc comment in
    `SwipeRevealPanel.alignment(for:)`.
  - **Declined/optional (not applied)**: literal SF Symbol string for
    `.complete` in `SwipeRevealPanel.presentation`, and the bottom-bar button
    keeping the `circle.slash` glyph while announcing "More" — both cosmetic,
    glyph scoped out by design decision 4/5.
- **Remaining manual items** (from `plan.md` / `implement.md`, still unconfirmed
  by an implement/review agent — device/simulator + VoiceOver checks):
  - Left-drag past threshold on `iPhone 17` presents Skip / Reschedule / Delete
    and does not skip; right-drag still completes; under-threshold and
    vertical drags open nothing.
  - Toggle OFF: left swipe still opens the menu and the bottom bar shows only
    the mic; the bottom-bar button now correctly announces "Skip Reminder".
  - Reveal plate reads "More" with the ellipsis glyph; localizes to
    Mehr/その他/Plus/Más/更多.
  - VoiceOver: card rotor "More", bottom-bar "More", menu first item "Skip".
  - macOS: left swipe opens the shared Skip / Reschedule / Delete menu (new in
    review).
  - `canMutate == false` + left swipe: no crash; gate-redirect path unchanged.
