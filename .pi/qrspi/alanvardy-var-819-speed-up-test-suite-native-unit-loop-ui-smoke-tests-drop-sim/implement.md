# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | fb32bfd | Phase 1: Smoke-test content (new UI test surface) |
| 1-fix | 27d5e05 | Phase 1 fix: render the action cluster deterministically under --ui-testing |
| 2     | 52e1d22 | Phase 2: Collapse the superseded UI surface |
| 3     | c3ae079 | Phase 3: repoint the local unit loop at macOS native |
| 4     | e9811f3 | Phase 4: rewire CI to the smoke matrix |
| —     | 75bec01 | chore: commit QRSPI design artifacts for the test-suite speedup |

All 5 phase commits are pushed to `origin/alanvardy-var-819-speed-up-test-suite-native-unit-loop-ui-smoke-tests-drop-sim` (fast-forward `1efdab7..75bec01`).

## Automated Checks
- [x] Stage 1: iOS smoke `xcodebuild … -only-testing:SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` passes (full-path filter — the shorthand form silently matches zero tests on Xcode 26)
- [x] Stage 1: watch smoke `xcodebuild … -only-testing:SingleThreadWatchUITests/SingleThreadWatchUITests/testLaunchAndRenderSmoke` passes
- [x] `make format` idempotent (no diff) and `make lint` clean across all stages
- [x] Stage 2: collapsed targets compile, lint, and expose exactly one method each (`testLaunchAndRenderSmoke`); `rm -rf DerivedData` + `make periphery` clean
- [x] Stage 3: `./scripts/test.sh --unit-only` (and `make test`) runs `SingleThreadTests` natively on `platform=macOS`; 3 pre-existing macOS `EntitlementStoreTests` failures annotated, not debugged
- [x] Stage 4: `ci.yml` YAML parses clean; `actionlint` exits 1 only on pre-existing SC2086 info-level hints in untouched `DEVELOPMENT_TEAM=` steps (same hints present on `HEAD` before the change); only full-path smoke filters + target names remain, no `UI_GROUP_*`, no deleted-class references; `ui-tests-smoke` matrix is `["iPhone 17"]`

## Final Integration Gate
- [x] Full `./scripts/test.sh` gate (run-gate skill, managed worktree) — **INCONCLUSIVE / BLOCKED locally per plan rule**: both attempts aborted at the iOS UI smoke stage under local simulator runner-clone contention (`RequestDenied` launching `SingleThreadUITests.xctrunner`, dual iOS 26.5/27.0 runtimes). Per the plan's rule (stop after two UI-stage contention failures → CI authoritative), no third local attempt. The macOS-native unit phase — the branch's headline change — was verified **green separately** via the simulator-free lane (`--unit-only`): 544 passed, only the 3 documented pre-existing macOS `EntitlementStoreTests` host-state failures. The iOS/watch UI smoke verdict rests on the PR's CI run. Everything before the iOS UI stage passed on both attempts (runtime pruning, deployment-target guard, format, lint, iOS build-for-testing, watch build, Periphery); watch UI/unit and macOS unit phases of a *full* run were never reached locally.

## Manual Verification Items (from the plan)
- [ ] Run the iOS smoke and confirm the simulator shows the "Buy groceries" card (title, "!!", notes) and Complete/Skip/mic buttons before the audit runs (Stage 1)
- [ ] Run the watch smoke and confirm the watch shows the "Buy groceries" card (title, "!!", notes) (Stage 1)
- [ ] Confirm each `SingleThreadUITests` and `SingleThreadWatchUITests` target exposes exactly one `@MainActor func testLaunchAndRenderSmoke` (Stage 2)
- [ ] Confirm the full-pipeline phase list (dry-run by reading `scripts/test.sh`) shows the iOS-Sim unit phase gone and macOS unit still last (Stage 3)
- [ ] Read the merged `ui-tests-smoke` job and confirm every `-only-testing` name matches a surviving member from the Stage 2 file list (Stage 4)
- [ ] Confirm no `UI_GROUP_*` reference remains anywhere in `ci.yml` (Stage 4)

## Plan Discrepancies Noted (resolved / reported, no silent deviation)
1. **Full-path filters**: plan's Stage 4 job snippet shows the shorthand `-only-testing:…UITests/testLaunchAndRenderSmoke`, but the corrections + verification greps require the full `Target/ClassName/method` path; the full path was used (locally proven in Stages 1–2 to be the only form that executes tests).
2. **`unit-tests` matrix**: the Stage 4 verification text claims `unit-tests` has no matrix, but that job is untouched and legitimately retains `["iPhone 17", "iPad (A16)"]` — left intact per the plan's own "Untouched jobs" step.
3. **`actionlint` "parses clean"**: exits 1 solely on pre-existing info-level SC2086 hints (present on `HEAD` before the change); structural YAML/job validation is clean.