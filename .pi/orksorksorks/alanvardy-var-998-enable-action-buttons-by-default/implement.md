# Implementation Summary

Flip the `enableActionButtons` preference default from `false` to `true` at every
read site (iOS + watch) so a fresh install shows the Complete/Skip/Reschedule
cluster. All settings-toggle, App Group persistence, wire payload, and
`--ui-testing`/`--seed` seams unchanged.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `78bc5b59` | Phase 1: iOS read-site defaults + migration-guard tests |
| 2     | `11c09d6b` | Phase 2: watchOS read-site default + tests |
| support | `595aedd9` | fix: annotate MainActor-touching test structs for Xcode 27 strictness (test-only, pre-existing local-toolchain block) |
| support | `e7cbd557` | chore: remove DELETEME bootstrap marker |
| support | `5aceaad8` | chore: commit research medium for enable-action-buttons ticket |

All pushed to `origin/alanvardy-var-998-enable-action-buttons-by-default` (fast-forward).

## Automated Checks

- [x] `make format` — no diff after SwiftFormat (both phases)
- [x] `make lint` — SwiftLint `--strict` clean (both phases, 0 violations)
- [x] `make build` succeeds (Phase 1)
- [x] `scripts/test-one.sh EnableActionButtonsMigrationTests` passes — 3 cases ran (`standardOnlyValueIsCopiedToAppGroup`, `freshInstallLeavesNoAppGroupValue`, `existingAppGroupOffIsNotClobbered`)
- [x] `scripts/test-one.sh ActionButtonTests` passes — 5 cases incl. `freshViewModelDefaultsToActionButtonsOn`
- [x] `scripts/test-one.sh SettingsViewTests` passes — 15 cases incl. `enableActionButtonsDefaultsToOn`
- [x] `make watch-build` succeeds (Phase 2)
- [x] `make watch-test` passes — all 5 `ShowEnableActionButtonsStateTests` incl. new `unsetKeyDefaultsToOn`, `persistedOffStaysOff`

### Post-phase gate: ran once via run-gate; LOCAL FAIL on a proven pre-existing false positive (verdict in gate.md)

- [ ] `./scripts/test.sh` green via `run-gate` after both phases — **not green locally**: gate child `fab02b07` verdict FAIL at the **Periphery** step (format/lint PASS, iOS build PASS `** TEST BUILD SUCCEEDED **`, watch build PASS, then Periphery aborted before any test suite ran). Single finding: `ContentView.swift:337 — Unused property 'isShowingPurchase'`.
- [ ] `SingleThreadUITests.testLaunchAndRenderSmoke` still passes (seam unchanged) — **not run locally** (Periphery aborted the pipeline before test suites).

**Why the Periphery failure is pre-existing/local-env, not branch-caused** (gate subagent evidence):
- `git log -S 'isShowingPurchase' origin/main..HEAD` is empty; the branch's whole `ContentView.swift` diff vs `origin/main` is the one-line `enableActionButtons = false → true`.
- The property IS used at three SwiftUI `$`-binding sites (`ContentView.swift:304, 306, 534`); it resolves inconsistently in the Swift-6/Xcode-27 index store (no plain-identifier reads/writes).
- CI proved the identical code passes on Xcode 26.6: `origin/main` tip `c07086ae` has a green Periphery step on its lint run (check-run 34716358538); local is Xcode 27.0.
- Reproduced 3× locally in every scan mode (deterministic on this machine). No local Xcode 26.6 exists to cross-test.

Per repo convention (pre-existing failures: annotate, don't debug, CI is authoritative), the local gate was NOT re-run for this finding. PR #195 is draft with **no CI checks run yet** — pushing ready or amending the draft triggers the authoritative CI verdict (`./scripts/test.sh` on Xcode 26.6, which also covers `testLaunchAndRenderSmoke` and the mac tests).

## Manual Verification Items (from the plan)

- [ ] Confirm by inspection that `registerDefaults()` bodies and the migration guard at `AppViewModel.swift:115-124` are byte-for-byte unchanged (comment only). *(Phase 1 subagent inspected: guard byte-identical.)*
- [ ] Confirm by inspection that `AppViewModel.swift:231` and `:311-314` still force `AppGroup.defaults.set(true, forKey: "enableActionButtons")`. *(Subagent inspected: force-true intact.)*
- [ ] Confirm the Settings toggle write path is untouched: `SingleThread/ContentView+Settings.swift` `onChange(of: bag.enableActionButtons)` → `enableActionButtons = new`, and `InterfaceSettingsView.swift` `Toggle(isOn: $enableActionButtons)`. *(Subagent inspected: untouched.)*
- [ ] Confirm `SkippedReminderSyncService.swift` push (`:222`) / apply (`:483-486`) are untouched, so off-state still persists and syncs. *(Subagent inspected: untouched.)*
- [ ] Confirm `SingleThreadWatch/WatchAppViewModel.swift:43,82` and `WatchReminderViewModel.swift:24,50` consume `isEnabled` unchanged.
- [ ] Confirm `SingleThreadWatchTests/WatchSyncPipelineTests.swift:379-418` (receive-persists-then-hook, push-unchanged) still pass — off-state sync is unchanged.

## Known pre-existing local issues (not caused by this branch; flag, don't debug)

1. **Local Xcode 27.0 (Swift 6.4) vs CI-pinned 26.6**: `SingleThreadTests/ColorCrossPlatformTests.swift:10` and `SortOptionTests.swift` reference app-target `@MainActor`-isolated statics from unannotated test structs, which breaks the whole SingleThreadTests target compile under Xcode 27 — reproduced on a clean `origin/main` worktree. Fixed test-only in `595aedd9` (`@MainActor` annotations, 2 lines). CI (26.6) unaffected. Verified the whole SingleThreadTests target compiles before/after Phase 1.
2. **Three macOS EntitlementStoreTests failures are known local-only** (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary); CI mac-tests are green on fresh runners — the local gate may fail on these.
3. **Watch test destination**: `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` fails locally with Error 70 under the Xcode 27.0 runtime (device only exists on the 26.5 runtime); used the Makefile's documented `WATCH_TEST_SIM='platform=watchOS Simulator,id=…'` override for `make watch-test`. CI pins its own watch destination.

## Notes from implementation

- `scripts/test-one.sh` requires the `SingleThreadTests/` target prefix when the suite name alone is ambiguous; the plan's bare-suite spellings work via target-prefixed forms.
- Plan's Phase 2 verification line "`SIM= scripts/test-one.sh ShowEnableActionButtonsStateTests` is not applicable" is intentionally left unchecked (informational — watch destination differs; `make watch-test` is the targeted command).
- No production/source changes beyond the plan; the only out-of-plan change is the test-only `@MainActor` fix (approved by parent supervisor, in its own `fix:` commit).