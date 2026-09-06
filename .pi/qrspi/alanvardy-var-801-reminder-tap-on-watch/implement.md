# Implementation Summary — VAR-801: Reminder tap on watch

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `75f6fd0` | Add `cardTapped()` to watch view model with unit test |
| 2     | `f316699` | Tap refreshes watch reminder list without dialog |
| 3     | `03ee4f6` | Full gate verification (plan.md checkbox only) |

Out-of-band (not part of this ticket's phases, committed by the user mid-run):
| — | `2da46cc` | docs: apply cross-session agent-conventions learnings to AGENTS.md |

## Automated Checks
- [x] `make watch-test` — `WatchReminderViewModelTests.cardTappedTriggersRefreshCycle` green; all existing `SingleThreadWatchTests` suites green (Stage 1 + re-verified in Stage 2/3)
- [x] `make watch-build` — watch app target compiles with the new method
- [x] `make format` — applies cleanly
- [x] `make lint` — swiftformat `--lint` + swiftlint `--strict` clean (0 violations / 180 files)
- [x] `make watch-ui-test` — all remaining watch UI tests green (13 Flows + `testAccessibilityAudit` + `testLaunch`; the 2 confirmation-dialog tests are gone)
- [x] `./scripts/test.sh` — format, lint, iOS build, watch build, Periphery (no dead code), iOS unit (663), iOS UI (17), watch UI (13 Flows + a11y + launch), watch unit (incl. Stage 1 test), macOS unit (524 non-entitlement) all green — **modulo 2 known local-only macOS `EntitlementStoreTests` SKTestSession failures** (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`; pre-existing — `SingleThreadTests/EntitlementStoreTests.swift` untouched by this diff — CI mac-tests is green, repo AGENTS.md says don't debug, CI is authoritative)
- [x] `rg "isShowingRefreshConfirmation|deleteButton" SingleThreadWatch SingleThreadWatchUITests` → nothing (sanity-verified by the Stage 3 worker; the standalone `refreshButton` at `WatchReminderView.swift` ~line 203 remains, as expected)

## Manual Verification Items (from the plan)
- [ ] Open the watch app in the simulator: tapping the card still opens the Refresh/Delete dialog (unchanged — Stage 1 is additive); refresh still works behind the dialog.
- [ ] `.pi/qrspi/…/structure.md` checkpoint obedience: action-menu delete (`Flows:134-159`), nudge-delete (`Flows:189-222`), empty/all-done refresh (`Flows:255`), a11y audit, and the remaining 12 flow tests all pass (covered by `make watch-ui-test`).
- [ ] On the simulator: tapping the reminder card directly triggers the refresh (spinner appears briefly, list re-fetches) — no dialog. Delete is still reachable via the action menu (`--ui-testing-action-menu`) and the 6-skip nudge banner.
- [ ] Confirm no `refreshButton`/`deleteButton`/dialog references remain in the watch UI-test target beyond the standalone `refreshButton` identifier at `WatchReminderView.swift` (~line 206) — `rg "isShowingRefreshConfirmation|deleteButton" SingleThreadWatch SingleThreadWatchUITests` returns nothing (the standalone `refreshButton` is expected to remain).

## Observations
- **Plan count typo (Stage 2)**: plan.md said "12 remaining Flows tests"; the tree has 14 Flows tests, so 13 remain after deleting `testDeleteViaConfirmationDialogRemovesReminder`. The gate is `make watch-ui-test` green, which passed with the actual 13. No plan change made; the Stage 2 checkbox wording still says "12".
- **Plan correction on `@Bindable`**: `@Bindable var viewModel = viewModel` in `reminderCard` was **kept** (correcting `structure.md` Stage 2) — it still supplies `$` bindings for the nudge dialog, action-menu dialog, and reschedule sheet.
- **Uncommitted AGENTS.md edit**: present at session start (mtime 10:21, before phase work); the user committed it themselves as `2da46cc` mid-run. No action needed.
- **Simulator flukes**: one transient `RequestDenied` xctrunner launch error during the iOS UI stage self-recovered (stage succeeded); one OS SIGKILL during an early Stage 2 `make watch-ui-test` attempt (memory pressure) — clean rerun passed. Both were environmental, not code-related.
- **iPad leg**: the local `./scripts/test.sh` runs iOS unit/UI on iPhone 17 only; iPad (A16) is a CI matrix job not run by the local gate.
- The plan's Stage 1 test runs ~1 s due to `refreshMinimumDisplayDuration`; per plan, no injected duration was added (out of scope) — noted as a follow-up if the suite ever becomes slow.