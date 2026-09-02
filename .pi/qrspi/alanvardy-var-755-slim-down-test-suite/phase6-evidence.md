# Phase 6 Verification-Gate Evidence (2026-09-02)

## 1. Structural counter — all down vs before.json

| Metric | before.json | after | verdict |
|--------|------------|-------|---------|
| unit_tests | 552 | 398 | down |
| launches | 35 (iOS 24 + watch 11) | 17 (iOS 8 + watch 9) | down |
| settle_sleeps | 5 | 0 | down |
| forced_400ms | 4 | 0 | down |
| xcodebuild (file-wide grep) | 14 | 13 | down |
| unnamed_expect | 917 | 735 | down |
| assertion_mean | 1.83 | 2.34 | up |
| Issue.record | 3 | 4 | +1 = merged watch relaunch test's deliberate named fallback (`WatchSyncPipelineTests.swift:406`, from Phase 3) |

Counter command: `bash scripts/count_tests.sh` (exit 0).

## 2. Targeted wall-time — after vs before

- **Before (Phase 1)**: `xcodebuild -scheme SingleThread -only-testing:SingleThreadTests -destination "$SIM" -derivedDataPath DerivedData test`
  - SIM: `platform=iOS Simulator,id=D7AC0D41-275E-47C5-B603-BC7FA08D1BB4` (iPhone 17)
  - Cold (no DerivedData existed): **124 seconds**, exit 0
- **After (Phase 6)**: same command, DerivedData warm (build-cached from gate runs)
  - **40 seconds**, exit 0, `** TEST SUCCEEDED **`, 427 test cases
  - Note caching asymmetry: the after number includes no compile time (warm DerivedData), the before number was cold. The test-execution portion is the meaningful comparison and is ~½ the before.

## 3. Full gate (`bash scripts/test.sh`) — documented environmental UI-launch flake

Three `full`-mode runs, all failing **only** at the UI runner-launch:
- Run 1 (03:01 log): format → lint → build → watch build → periphery → unit all pass; `** TEST EXECUTE SUCCEEDED **` (427 unit tests); UI phase aborts at runner launch with `Busy ("Application failed preflight checks")` / `RequestDenied` (`SBMainWorkspace`), no UI test assertions executed.
- Run 2 (mid-gate, killed at session cap): unit passed; UI phase started, ran many tests but with heavy `DebuggerLLDB.DebuggerVersionStore.StoreError` degradation and one a11y-audit failure before the session died.
- Run 3 (detached, nohup → pid died with session): identical to Run 1 — unit passed, UI runner-launch `Busy` failure.

**Isolation proof (same clean environment)**:
- `bash scripts/test.sh --ui-only` → `** TEST EXECUTE SUCCEEDED **`, **42/42 UI tests passed**, `✅ UI tests passed.` — includes the a11y audit test that flaked in degraded Run 2.
- `testCancelOnForeground` (flaked in an earlier degraded run) passes 2× in isolation.
- `ActionButtonsUITests.swift` (a11y audit) diffed empty in Phase 4 — untouched.

**Conclusion**: the full-gate failure is the AGENTS.md-documented simulator `Busy`/`RequestDenied` runner-launch flake arising from unit→UI sequential clone handoff in `full` mode, not a Phase 2–5 regression. All automated structural and timing checks pass. Re-running `bash scripts/test.sh` on a host simulator that services back-to-back clone launches is the single remaining (environmental) item before end-to-end green.

## 4. Files changed in Phase 6

- `.pi/qrspi/alanvardy-var-755-slim-down-test-suite/plan.md` — Phase 6 automated checkboxes checked, full-gate outcome documented
- No source/test code changed (Phase 6 is verification-only per plan)

## 5. Addendum — pre-Phase-5 control run (proves the flake is environmental)

After the three full-mode runs above plus two more parent-side attempts (cold-erased sim, warm sim),
the same `Busy ("Application failed preflight checks")` UI-runner launch denial persisted. To rule out
a Phase 5 regression, the parent ran the **pre-Phase-5 `scripts/test.sh`** (restored from commit
`472a9c0`) as a control (logged at `/tmp/gate_old.log`, pid 49394):

- format → lint → build → watch build → periphery → **unit passed** (`TEST EXECUTE SUCCEEDED`)
- **UI phase**: identical failure — `Failed to launch app.alanvardy.SingleThreadUITests.xctrunner`,
  `SBMainWorkspace … reason: Busy ("Application failed preflight checks")` at the very first runner launch.

**Conclusion**: the full-gate UI-launch flake is **pre-existing environmental simulator contention**
(AGENTS.md-documented `Busy`/`RequestDenied` runner-launch failure), reproduced identically with and
without Phase 5's changes. No Phase 2–5 code is implicated. Every phase passes in isolation:
- exact Phase 5 unit command passes 2× standalone (clones, `-parallel-testing-enabled YES`)
- iOS UI suite passes 42/42 via `--ui-only` on this same host
- watch unit + UI suites pass (Phase 4/6 runs)
- macOS build (`build CODE_SIGNING_ALLOWED=NO`) passes standalone (exit 0)

The `test.sh` control copy was reverted; working tree is clean at `74aa114` with the Phase 5 runner restored.