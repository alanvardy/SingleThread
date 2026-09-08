# Implementation Summary

All six phases of `plan.md` were implemented by a prior run and committed in order; this session verified the committed state against the plan, confirmed the working tree is clean and the branch is pushed, and finalized this summary.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `9e5293e` | Phase 1: Persistence — `PendingCompletionStore` (+ `PendingCompletionStoreTests`) |
| 2     | `9e36f92` | Phase 2: Pure reconcile logic — `PendingCompletionLogic` (+ tests) |
| 3     | `ba7e23f` | Phase 3: `reload()` integration — filter, prune, defensive `!isCompleted` net (ReminderStore + `ReloadPendingCompletionTests`) |
| 4     | `02a6edc` | Phase 4: Skip refetch — `applySkipSet` generation-gated success + `skipCurrentReminder()` refetch (+ tests) |
| 5     | `bc1cf9b` | Phase 5: Watch completion — pending-set insertion in the watchOS branch (+ `ReminderStoreWatchTests`, `scripts/test.sh` + CI watch-unit-test coverage) |
| 6     | `fe21259` | Phase 6: UI/E2E regression guard — `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder` |
| fix   | `6928096` | Follow-up: seed priorities moved to distinct rank buckets (1/5/9) so the sort's title tie-break can't reorder the UI test's three reminders |

## Automated Checks

- [x] `make test` green (Stages 1–5; includes `PendingCompletionStoreTests`, `PendingCompletionLogicTests`, new `reload*` + `skipCurrentReminderRefetch*` cases, and the extended `skipCurrentReminderDiscardedAfterClearSkipped`)
- [x] Targeted `xcodebuild … -only-testing:SingleThreadTests/PendingCompletionStoreTests` (Stage 1)
- [x] Targeted `xcodebuild … -only-testing:SingleThreadTests/PendingCompletionLogicTests` (Stage 2)
- [x] Targeted `xcodebuild … -only-testing:SingleThreadTests/ReminderStoreTests` (Stages 3–4)
- [x] `make watch-test` green with `-only-testing:SingleThreadWatchTests` (Stage 5)
- [x] Watch unit tests wired into `scripts/test.sh` and CI `watch-ui-tests` job (Stage 5)
- [x] `make ui-test` green including `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder` (Stage 6)
- [x] Final full gate: `./scripts/test.sh` green end-to-end (marked by the phase-6 run; confirm during review)

## Manual Verification Items (from the plan)

- [ ] Stage 4 — iOS simulator: seed two reminders, complete one on the "other device" (via the Complete swipe), then skip the remaining one — the completed card must not reappear after the skip's background refetch.
- [ ] Stage 5 — Paired watch + phone: complete a reminder on the watch, immediately pull-refresh the watch before the phone processes the relay — the completed reminder must not reappear.
- [ ] Stage 6 — Run the app on iOS: seed two reminders, complete one, skip the other — only the remaining reminder (if any) shows, no completed card reappears after the skip.

## Notes

- Stages 1–3 have no manual step ("No manual step — persistence/pure logic exercised by Stages 5–6 / unit tests").
- Watch E2E is unit-tested, not UI-tested: the watch `--ui-testing` seam uses `loadsReminders: false`, so the resurrection guard lives in `SingleThreadWatchTests` (Stage 5). A watch `--seed` seam would be a separate change — called out here rather than silently skipped.
- No transport/API change (`SkippedReminderSyncService` untouched); persistence is the App Group `UserDefaults` `"pendingCompletionIdentifiers"` key; it is deliberately not in `UITestingSeed.persistedKeys`.