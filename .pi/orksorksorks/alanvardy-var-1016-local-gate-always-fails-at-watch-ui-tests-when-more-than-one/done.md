# Done

- **What was built**: Fixed the local full gate's Watch UI tests stage so it no
  longer dies on machines with multiple watchOS runtimes. `scripts/test.sh`
  now resolves the name-only `WATCH_TEST_SIM` default to the matching device's
  UDID (and pre-boots it) before the watch stage, or fails fast with an
  actionable "no watch simulator matches <name>" message instead of the opaque
  xcodebuild destination error; `Makefile` mirrors this by defaulting
  `WATCH_TEST_SIM` to the resolved `id=` form (parse-time, with the name-form
  fallback) so `make watch-ui-test` / `watch-test` work on multi-runtime
  machines too. `WATCH_TEST_SIM` env/CLI overrides keep winning; CI
  (`.github/workflows/ci.yml`, pins `id=` and never reads `WATCH_TEST_SIM`) is
  untouched. The bootstrap `DELETEME` marker was removed.
- **Commit SHA(s)**: `d14cc022` (implementation + DELETEME removal + small.md
  artifact), `e7528271` (chore: record small-phase completion). Both pushed.
- **Verification**: `bash -n scripts/test.sh` passed; harness exercising the
  real preflight block resolved `Apple Watch Series 11 (46mm)` →
  `platform=watchOS Simulator,id=3F69EA19-301C-4978-AA7B-A63DE7CE69F5` and
  pre-booted it (exit 0); the nonexistent-name case printed the actionable
  message + available-watch-simulator listing and exited 1; `,id=…` overrides
  pass through untouched (incl. CLI/env and `,OS=`-suffixed name overrides);
  `make -pn` shows the default `WATCH_TEST_SIM` =
  `platform=watchOS Simulator,id=3F69EA19-…` with CLI/env overrides winning and
  the name-form fallback preserved. `make format` + `make lint` clean (0
  violations). Full multi-hour `./scripts/test.sh` gate launched once via the
  run-gate skill after commits — verdict appended below when it completes.
- **Reviewer findings**: 0 blockers. 4 optional P2 nits, deferred (each mirrors
  a pre-existing iOS pattern or a convenience-only make target): (1) the
  `Makefile` parse-time `$(shell xcrun simctl …)` runs on every make invocation
  (~1s, consistent with the existing `SIM_FROM_WORKTREE` shell-out); (2)
  `make watch-ui-test`/`watch-test` have no fail-fast path (xcodebuild still
  errors opaquely on an unresolvable name — only the gate preflights); (3) a
  user-supplied stale `id=` override bypasses the actionable preflight and can
  die at `bootstatus` (same exposure as the iOS path); (4) `set -euo pipefail`
  surfaces a raw `simctl` error if the `simctl list` command itself fails
  (same pre-existing behavior as the iOS resolution).
- **Remaining manual items**: full-gate verdict pending (acceptance criterion).