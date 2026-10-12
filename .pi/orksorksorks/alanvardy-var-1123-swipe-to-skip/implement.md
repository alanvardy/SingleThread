# Implementation Summary

Ticket: VAR-1123 — swipe-to-skip
Branch: `alanvardy-var-1123-swipe-to-skip`

End state: on iOS a left swipe past the 72 pt release threshold presents the
existing Skip / Reschedule / Delete `.confirmationDialog` instead of skipping
directly. The reveal panel and both "More" triggers read a new shared `More`
key (`ellipsis.circle.fill`); the menu's first item is still "Skip". macOS and
the watch are behaviorally unchanged.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| bootstrap | `30ee43ae` | chore: remove DELETEME bootstrap marker |
| 1 | `fb5ad6c9` | Phase 1: Left swipe opens the action menu |
| 2 | `233dda57` | Phase 2: More — relabel swipe surface and bottom-bar button |
| 3 | — (no source change) | Phase 3: Hardening & verification — format/lint/smoke/Periphery only |

Phase 1 and Phase 2 are pushed to `origin/alanvardy-var-1123-swipe-to-skip`.
Phase 3 made no file changes, so it has no commit (empty commits forbidden).

## Automated Checks

- [x] `make build` passed
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` green (10 cases)
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` green (6 cases)
- [x] `scripts/test-one.sh SingleThreadTests/AppLanguageTests` green (8 cases; all six locales resolve)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeCompletesReminder` green (right swipe unchanged)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeOpensActionMenu` green
- [x] `make format` idempotent, `make lint` clean (`swiftlint --strict`, 0 violations)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` green (accessibility audit re-passes with renamed labels + relocated dialog)
- [x] `rm -rf DerivedData && make periphery` clean after a fresh build index
- [ ] Full `./scripts/test.sh` run ONCE via the `run-gate` skill — **deferred to the review step** (the implement step does not run the project-wide gate; the plan and the run-gate skill place it at the handoff)

## Manual Verification Items (from the plan)

### Phase 1
- [ ] On `iPhone 17` simulator (`SIM=` pinned from `.simulator_id`): left-drag the card past ~half its width → the Skip / Reschedule / Delete action sheet appears; the card is not skipped (same reminder still visible after dismissing).
- [ ] Right-drag past threshold still completes the reminder.
- [ ] Under-threshold left drag and a vertical-dominant drag open nothing.
- [ ] Settings → action-buttons toggle **OFF**, relaunch: left swipe still opens the action sheet; the bottom bar shows the mic only. Tap Reschedule in that sheet → the reschedule sheet presents (no stuck dialog).
- [ ] Simultaneously drag left and release while the reminder is mid-scroll: List scrolling still works (vertical dominance guard).

### Phase 2
- [ ] Swipe left partway on the card: the reveal plate at the trailing edge reads **More** with an ellipsis-in-circle glyph.
- [ ] VoiceOver on the card: the left-swipe rotor action is announced "More"; the bottom-bar action button announces "More"; inside the opened menu the first item is still announced "Skip".
- [ ] Switch the language picker to Deutsch/日本語/Français: the reveal plate reads Mehr/その他/Plus.

### Phase 3
- [ ] Swipe left: the reveal plate animates back to offset 0 and does **not** linger/restart under the presented action sheet.
- [ ] With the toggle OFF, swipe-open menu still works, and `enableActionButtons` still hides only the bottom-bar cluster (Settings toggle ON/OFF round-trip).
- [ ] `canMutate == false` (e.g. reminders access revoked) + left swipe: no crash; the gate-redirect path behaves as before.
- [ ] VoiceOver full pass: card, action button, and dialog items all announce sensibly; nothing announces "Skip" on the two "More" triggers.

## Notes / Observations

- Phase 1 was implemented by a worker but, due to a missing task handoff, did
  not commit; the parent reviewed the diff (7 files, in-scope) and committed it
  as `fb5ad6c9`.
- The dialog host moved to `ContentView.body` (design deviation 1) so it
  presents even when the bottom-bar cluster is off-screen (toggle off /
  entitlement / mutate gate). Still one binding, one presenter.
- The `.more` dispatch is `#if os(iOS)`-branched; macOS keeps
  `skipCurrentReminder()` (design decision 9).
- `SwipeRevealPanel.systemImage(for:)` was extracted so the ellipsis glyph is
  assertable (design deviation 3).
- No manual verifications were confirmed by the implement step; all are left
  for the user.