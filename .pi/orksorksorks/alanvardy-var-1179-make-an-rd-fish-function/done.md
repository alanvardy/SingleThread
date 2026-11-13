# Done

- **Branch / head SHA**: `alanvardy-var-1179-make-an-rd-fish-function` @
  `75b392ac` (`chore: record implement artifacts for VAR-1179`); in sync with
  `origin` (`git rev-list --left-right --count HEAD...origin/...` → `0 0`).
  HEAD is rebased on `main` (`46844600`); no conflicts were present.
  Phase 2 (`rd.fish`) is on dotfiles `main` @ `1ba21e5` — not on this branch.

- **Mechanical checks** (all pass, shell-only diff):
  - `bash -n scripts/run-devices.sh` — OK
  - `bash -n scripts/test-run-devices.sh` — OK
  - `shellcheck -S warning --exclude=SC1111 scripts/run-devices.sh` — OK
  - `shellcheck -S warning --exclude=SC1111 scripts/test-run-devices.sh` — OK
  - `bash scripts/test-run-devices.sh` — all pass, including the two new duo
    filter assertions and the happy/sad duo flow cases.
  - No warnings flagged. The full iOS gate was not re-run here: the diff is
    shell-only and `scripts/test-run-devices.sh` is not wired into
    `scripts/test.sh`; the plan's post-plan gate remains the regression check.

- **Review outcome**: one bounded `reviewer` pass over the full diff + dotfiles
  wrapper. **No blockers, no fixes worth doing now.** Verified independently:
  env-parse ordering/opt-back-in is sound under `set -euo pipefail`; duo reuses
  the Duo-only discovery filter and the `!= "sim"` zero-device fail-fast;
  sim/watch/macOS legs are skipped; summary and toast never mislabel the leg or
  print `0 simulator(s)`; the new negative assertions are non-vacuous (their
  grepped strings exist in `run-devices.sh`).
  - Optional (declined/deferred): (1) duo-mode "no device" error still reads
    "No reachable iPhone/iPad found." — honest but not Duo-specific; (2) the
    duo flow test's `want_absent` guards the summary line but not the toast, so
    a regression re-adding `and 0 simulator(s)` would slip through; (3) the
    "no physical iPhone Duo found" notice is `== "sim"` only, so
    `IOS_TARGET=duo RUN_MAC=1` with no Duo runs macOS with no Duo hint
    (intentional per plan).

- **Remaining manual items**: the plan's on-device checks were not exercised
  (no physical Duo in this session) — with the Duo paired/reachable,
  `IOS_TARGET=duo ./scripts/run-devices.sh` should build/install/launch only
  the Duo and print `iPhone Duo (device): 1/1 launched, 0 unreachable`; with no
  Duo it should exit non-zero without touching sim/watch/macOS; and
  `IOS_TARGET=duo RUN_WATCH=1 RUN_MAC=1` should re-enable those legs
  (plan.md Verification → Manual). Post-plan gate (`./scripts/test.sh` via the
  `run-gate` skill) is still outstanding if a regression check is wanted.
