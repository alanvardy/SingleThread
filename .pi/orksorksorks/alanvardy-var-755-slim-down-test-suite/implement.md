# Implementation Summary

**Ticket**: `alanvardy-var-755-slim-down-test-suite`
**Date**: 2026-09-02
**Branch**: `alanvardy-var-755-slim-down-test-suite`

Slim the local test suite along three axes — consolidate one-assertion floods into named-assertion
tests, delete true cross-target duplicates, and shrink sleeps / launch counts / runner invocations —
with the runner deduped and a verification gate proving the slimmer state.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | 16e75ed | Re-baseline plan measurement expectations to actual repo counts (pre-implementation fix: the plan's 65/50-launch and 9-xcodebuild baselines didn't reproduce — actual 35 / 14) |
| 1     | 0b6193e | Phase 1: Measurement substrate (structural proxy counter) — `scripts/count_tests.sh`, `before.json`, before wall-time capture (124 s cold) |
| 2     | 2c383de | Phase 2: Deterministic settle seam (SingleThreadCore) — injectable `settle:` on `ReminderStore`, 5 sleeps → hook, 4 forced 400 ms test sleeps removed |
| 3     | 2bbb7eb | Phase 3: Unit-test consolidation & dedupe (iOS + watch) — 23 files, 552 → 398 `@Test`s, mean 1.83 → 2.34 |
| 4     | 472a9c0 | Phase 4: UI-test scaffolding dedup & launch reduction — `SingleThreadUITestCase` base, 4 classes migrated, persistence-relaunch tests merged, 2 watch glow dupes deleted |
| 5     | 39ccfc2 | Phase 5: Runner restructuring — `scripts/test.sh` pins `id=<UDID>` + pre-boots sim, adds CI-proven unit-phase flags, deletes the macOS unit-test run (keeps macOS build) |
| 6     | 74aa114 | Phase 6: Verification gate — counter + timing evidence, plan.md boxes |
| 6     | 74d7b07 | Phase 6: document pre-Phase-5 control run proving gate flake is environmental |
| 6     | 6f3c19b | Phase 6: green full gate achieved (fresh watch simulator) |

## Automated Checks

- [x] `scripts/count_tests.sh` reproduces Phase 1 baselines exactly (552 / 962 / 46 / 1.83 / 35 / 5 / 4 / 14 / 917)
- [x] Phase 2: `settle_sleeps` 5 → **0**, `forced_400ms` 4 → **0**; iOS unit suite green twice (determinism, default + injected settle)
- [x] Phase 3: `unit_tests` 552 → **398** (iOS 370, watch 28); `assertion_mean` 1.83 → **2.34**; `unnamed_expect` 917 → **735**; `addReminderWithInMemoryStoreDoesNotCrash` (zero-assertion) gone; iOS unit green (427) + watch unit green (32)
- [x] Phase 4: `launches` 35 → **17** (iOS 24 → 8, watch 11 → 9); `grep "private func launchApp\|private func flipToggle"` → 0; iOS UI green (41) + watch UI green (24)
- [x] Phase 5: `xcodebuild` file-wide 14 → **13** (full-mode 9 → 8); `bash -n` clean; diff shows only destination-pinning + unit flags + macOS-test removal
- [x] Phase 6: every structural metric down vs `before.json`, none regressed; targeted unit wall-time **40 s** (warm) < **124 s** (Phase 1 cold baseline)
- [x] Phase 6: **full `bash scripts/test.sh` green end-to-end** — format → lint → build → watch build → periphery → unit (427) → iOS UI → watch UI → watch unit → macOS build → `✅ All CI checks passed.` (exit 0)

## Manual Verification Items (from the plan)

- [ ] **Phase 1**: Review the captured before unit wall time (124 s cold) in `before-time-notes.md`
- [ ] **Phase 2**: Grep confirms zero `eventKitSettleDelay` remains in `ReminderStore.swift`; the default-settle path (no injection) still runs deterministically — the seam, not blind deletion, removed the wait
- [ ] **Phase 3**: Spot-check merged `#expect(…, "…")` messages name the specific input/field; confirm no cross-suite merge broke a `@Suite(.serialized)` boundary
- [ ] **Phase 4**: Confirm no persistence assertion lost (bg-off, pin-on, pin-off, list-on, glow-off, swipe-dismissed each still asserted); `--seed` only for write flows, `--ui-testing` for every persistence relaunch
- [ ] **Phase 5**: Diff-review changed `test.sh` blocks against `ci.yml:48-52` (pre-boot) and `ci.yml:129-136` (allowance/parallel); confirm macOS `build` runs and macOS `test` does not
- [x] **Phase 6**: Full gate green end-to-end (see Automated Checks; evidence in `phase6-evidence.md` §6)

## Observations / Deviations

- The plan's measurement baselines did not match the repo (launches 65 vs actual 35; xcodebuild 9 vs
  actual 14 file-wide). Re-baselined in `plan.md` (commit 16e75ed) — the counter's own formulas now
  reproduce exactly; implementation steps unchanged.
- Phase 2: `await Task.yield(); await Task.yield()` proved insufficient on parallel test clones for the
  skip-path Task (settle → apply → reload chain spans an off-main continuation hop). Used the repo's
  existing `withCheckedContinuation` hook-rendezvous pattern instead (zero sleeps, deterministic).
  SwiftLint's `trailing_closure` rejects `settle: {}`, so tests use a named `noopSettle` constant.
- Phase 3: SwiftLint opt-in `large_tuple` and Swift Testing's `Sendable` requirement blocked the plan's
  raw tuple tables and `[EKRecurrenceRule]?` parameterization; converted to private named record
  structs / non-parameterized multi-assertion tests. `ShowCompletionGlowStateTests` has 7 (not 5)
  transition tests, so it lands at 10 tests, not the plan's stated 8. `Issue.record` 3 → 4 from a
  defensive named fallback in the merged watch relaunch test.
- Phase 4: launch count (35 → 17) beats the plan's target because centralizing `.launch()` collapsed
  inline source sites; every persistence direction still asserted.
- Phase 6: the full gate's earlier `Busy` / `NotFound` failures were proven **environmental** — the
  pre-Phase-5 `test.sh` control reproduces the identical UI `Busy` flake, and a fresh unpaired watch
  sim passes the full watch build→UI→unit sequence while the reused (erased) one does not. The watch
  phase is byte-identical pre/post Phase 5. Final green run used the `WATCH_TEST_SIM` id override
  that AGENTS.md already documents for ambiguous-name machines.