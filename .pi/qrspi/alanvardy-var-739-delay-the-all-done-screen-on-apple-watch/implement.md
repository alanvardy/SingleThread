# Implementation Summary

Delays the watchOS "all done" screen: after Complete is tapped, the reminder card stays
visible as a ghost behind the fading green glow, then yields to the empty state once the
glow has finished.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `ba77212` | Completion transition state & logic in `WatchReminderViewModel` — adds `isShowingCompletionTransition`, `transitionReminder`, `completionTransitionBuffer`; reworks `completeCurrentReminder()` to snapshot the card, hold it for `glow.duration + buffer`, and only clear it if the store is still empty. Adds 7 unit tests to `ShowCompletionGlowStateTests`. |
| 2     | `5ecbe5c` | Ghost-card branch in `WatchReminderView` — `reminderContent` renders `transitionReminder` first while the transition flag is set, so the card persists under the glow overlay. |
| 3     | `1f183b6` | Post-completion timing UI test — `testCompleteHoldsCardDuringGlow` asserts the card persists during the glow and the `No Reminders` state appears afterwards. |

## Automated Checks

- [x] `make watch-test` passes — all 7 new transition tests green, existing watch unit tests unchanged
- [x] `make watch-ui-test` — all watch UI tests green (no regressions), incl. new `testCompleteHoldsCardDuringGlow`
- [x] `make build` passes (iOS scheme builds without regressions)
- [x] `make watch-build` compiles cleanly
- [x] `./scripts/test.sh` — full CI gate passes: format, lint, build, watch build, Periphery, iOS unit tests, iOS UI tests, watch UI tests, macOS build + tests
- [x] Periphery `--strict` reports no unused declarations (transition properties are read by the view and tests)

### Note on the full gate

The first full `./scripts/test.sh` run failed in three **pre-existing** iOS unit tests
(`CompletionGlowViewModelTests.glowTriggersOnSuccessfulCompletion`,
`glowTriggersWhenPreferenceEnabled`, `ReminderStoreWriteTests.completeReminderMarksSavedAndReloads`).
Root cause was **local simulator state pollution**, not this change: the dev simulator's App
Group (`group.app.alanvardy.SingleThread`) had `completionCount = 100` persisted from earlier
freemium work. With the gate `canMutate = isEntitled || count < 100` and no entitlement,
`ReminderStore.completeReminder()` returns `false`, so the glow never triggers. This reproduced
identically on a clean `origin/main` worktree (proving it pre-dates this branch). Clearing the
stale `completionCount` key restored the pristine state CI would see; the full gate then passed.

## Manual Verification Items (from the plan)

- [ ] **Stage 1**: Build and run the watch app in the simulator via `make watch-build` to confirm it compiles (flag exists but nothing reads it yet).
- [ ] **Stage 2**: `make watch-build` succeeds.
- [ ] **Stage 2**: Run the watch app in the simulator — complete a reminder and confirm:
  - The card does **not** vanish instantly
  - The green glow fades over the card
  - The empty state ("No Reminders") appears after ~1 second
- [ ] **Stage 2**: Spot-check skip and delete — both still work without visual regressions.
- [ ] **Stage 3**: No Periphery warnings for unused declarations (the new properties are read by the view and tests) — *confirmed by the full gate's `periphery scan --strict`*.
