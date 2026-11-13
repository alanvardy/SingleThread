# Done

- **Branch / head SHA**: `alanvardy-var-1172-add-screenshots-for-the-iphone-duo` / `9dabb902`
  (review fixes on top of the four phase commits; branch already rebased onto `main`
  `50718721`, which is an ancestor of HEAD — no rebase conflicts remained).
- **Mechanical checks**: all green
  - `bash -n scripts/appstore-screenshots.sh` — exit 0
  - `shellcheck -S warning scripts/appstore-screenshots.sh` — **clean** (was 7 new findings)
  - `bash scripts/appstore-screenshots.sh --help` — full doc block incl. the Usage lines
  - `make format` — no changes; `make lint` — 0 violations, 0 serious
  - `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` — 6 cases, ok
  - `scripts/test-one.sh SingleThreadTests/LaunchArgumentTests` — 9 cases, ok
  - Full CI-identical gate (`./scripts/test.sh`) runs in the downstream `run-gate` step,
    not here — per the repo's gate-staging convention.
- **Review outcome**: one bounded fresh-context `reviewer`; no P0/P1 blockers.
  - **Fixes applied now (review commit `9dabb902`)**:
    1. Stale wallpaper doc counts: "ten" → "fifteen" in both places, plus a note that
       `iphone-duo` reuses the five `iphone-duo-<screen>` slots.
    2. Corrected a newly-introduced doc error: "all seven languages" → "all six" (the
       `LANGUAGES` array has six entries: `en zh-Hans fr de ja es`).
    3. `duo_six_shots`: renamed `local display` → `local screen_id`, clearing the seven
       new shellcheck findings (main was clean; they were introduced by Phase 1, not
       pre-existing as `implement.md` had claimed).
    4. Reworded the `LaunchArgument.orientation` doc comment — only `landscape` is
       honored; any other token is ignored.
    5. Realigned the `--help` `sed` range `2,163p` → `2,166p` after the doc additions
       shifted the block boundary (caught during re-verification).
  - **Optional polish applied**: refreshed the `implement.md` push/shellcheck
    observations to reflect the force-push and the cleared findings.
  - **Feedback ignored/deferred**: `applyForcedOrientationIfNeeded()` running on every
    `applicationDidBecomeActive` is launch-arg-gated and harmless — left as-is.
- **Remaining manual items** (cannot be exercised headlessly — need the Duo simulator
  with the hinge pose set in Device Hub before each run, so they are deferred to the user):
  - `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo` → reports
    `7×6 screenshots, every size accepted`; `4-duo-outer-portrait/` = 1398 × 2034,
    `5-duo-outer-landscape/` = 2034 × 1398; `1-main-dark.png` shows the widened Duo card.
  - `… --no-build --no-install --duo-pose book iphone-duo` → `6-duo-inner-portrait/` =
    2007 × 2853, standard 40-inset layout.
  - `… --no-build --no-install --duo-pose open iphone-duo` → `7-duo-inner-landscape/` =
    2853 × 2007.
  - `--fetch-wallpapers` resolves all five `iphone-duo-*` slots (all five are committed).
  - Full three-invocation sweep across all six languages.
