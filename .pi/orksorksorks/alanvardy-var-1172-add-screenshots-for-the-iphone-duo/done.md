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

## Post-review change — `iphone-duo` joins the default class list

Reviewer feedback: a bare `scripts/appstore-screenshots.sh` run should include
`iphone-duo`. Reverses the earlier opt-in decision. Three coordinated edits:

1. Default `CLASSES` now ends `… watch-series11-46mm iphone-duo`.
2. `DUO_POSE` defaults to `folded`, so a bare run captures the outer portrait +
   landscape variants without a `--duo-pose` flag. The inner panel still needs an
   explicit `book`/`open` pose — a single run captures one physical hinge posture
   (no headless hinge API).
3. `capture_duo`'s missing-simulator path now warns and `return 0` instead of
   `exit 1`; a function `return 1` inside the class loop aborts the whole script
   under `set -e`, and the iPhone19,4 runtime is not on every machine.

Header docs and the `--help` `sed` range (`2,166p` → `2,169p`) were realigned to
the shifted block boundary. Re-verified: `bash -n` clean, `shellcheck -S warning`
clean, `--help` prints the full block. Head SHA below this line is superseded by
the follow-up commit.

## Manual Duo run — two latent bugs found and fixed

First real folded capture surfaced two defects that the earlier "deferred to the
user" checks had never exercised:

1. **Reminders TCC prompt in every shot.** The harness never pre-granted EventKit
   access, so the first `--seed` launch raised the system alert — which then stays
   on SpringBoard and bleeds into every later screenshot (no tap command can
   dismiss it). Fix: `grant_reminder_access` calls `simctl privacy … grant
   reminders` for each iOS class after install.
2. **"Landscape" shots were portrait.** `5-duo-outer-landscape/*.png` came out
   1398 × 2034, byte-identical to the portrait set. `applyForcedOrientationIfNeeded`
   requested landscape geometry but `supportedInterfaceOrientationsFor` still
   advertised portrait, so the Duo cover display kept portrait. Fix: extract
   `AppDelegate.supportedOrientations(forcedOrientation:allowsLandscape:)`,
   which returns `.landscape` when the harness forces it; the delegate feeds it
   `LaunchArgument.orientationValue()`. Regression tests added in
   `AppDelegateTests` (6 cases, all green).

Re-verified end to end: `appstore-screenshots.sh --no-build --duo-pose folded
iphone-duo` → **72 screenshots, every size accepted**, unique dimensions
`1398 × 2034` / `2034 × 1398`, no TCC alert in the seed shots, `make format` +
`make lint` clean.
