# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `a277cfcf` | Phase 1: walking skeleton — folded outer portrait, end to end |
| 2 | `b1f7ab3b` | Phase 2: folded outer landscape, end to end |
| 3 | `b64b91a1` | Phase 3: inner display, both poses, end to end |
| 4 | `9cfe8ff4` | Phase 4: hardening & documentation |

Base before Phase 1: `5fa8f3cd` (chore: record structure artifact for VAR-1172).
Each commit contains only its own phase's files; `plan.md` and `.pi/` artifacts
were never staged.

## Automated Checks

- [x] `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` — `ok: 6 case(s) ran`
      (includes new `forceFlagReturnsDuoContext`).
- [x] `scripts/test-one.sh SingleThreadTests/LaunchArgumentTests` — `ok: 9 case(s) ran`
      (includes new `orientationValueParsesLandscape`, `orientationValueAbsentIsNil`).
- [x] `bash -n scripts/appstore-screenshots.sh` — exit 0.
- [x] `bash scripts/appstore-screenshots.sh --help` — prints the full doc block through
      the `Usage:` + `class: … | iphone-duo` lines (sed range realigned to `2,163p`).
- [x] `shellcheck -S warning scripts/appstore-screenshots.sh` — 7 findings, all
      pre-existing (SC2178 + 6× SC2128 in `duo_six_shots`); Phase 4 introduced none.
- [x] `make format && make lint` — 0 violations, 0 serious in 243 files.
- [x] Five `iphone-duo-*` wallpaper slots fetched and committed
      (`iphone-duo-main-dark`, `iphone-duo-empty`, `iphone-duo-options`,
      `iphone-duo-main-light`, `iphone-duo-no-reminders`) + manifest entries.

Note: the plan's Phase 4 automated item `make test` (full unit-only gate) was
substituted with the two targeted seam suites via `scripts/test-one.sh` to keep
the phase bounded; the full `make test` / CI-identical gate runs in the
`run-gate` step.

## Manual Verification Items (from the plan)

### Phase 1
- [ ] In Device Hub, set the Duo to **folded**, then run
      `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo`.
- [ ] The run reports `7×6 screenshots, every size accepted` and every file under
      `build/appstore-screenshots/*/4-duo-outer-portrait/` is 1398 × 2034
      (`for f in build/appstore-screenshots/*/4-duo-outer-portrait/*.png; do sips -g pixelWidth -g pixelHeight "$f"; done`).
- [ ] `1-main-dark.png` shows the **widened** Duo card (gutter 20, cap
      `min(340, w*0.8)`), not the standard 40-inset card.
- [ ] `git status` shows exactly the 5 new `iphone-duo-*.jpg` + modified
      `manifest.json` under `scripts/fixtures/appstore-wallpapers/`.

### Phase 2
- [ ] Device Hub pose **folded**; `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo`
      reports every size accepted.
- [ ] `build/appstore-screenshots/en/4-duo-outer-portrait/` is 1398 × 2034 and
      `build/appstore-screenshots/en/5-duo-outer-landscape/` is 2034 × 1398.
- [ ] Spot-check `5-duo-outer-landscape/1-main-dark.png`: content is rotated
      landscape (not a letterboxed portrait), card still widened.
- [ ] Stop and re-open the design's orientation decision if `requestGeometryUpdate`
      proves flaky on the Duo runtime.

### Phase 3
- [ ] Device Hub pose **book**;
      `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose book iphone-duo`
      reports every size accepted; `6-duo-inner-portrait/` files are 2007 × 2853.
- [ ] Device Hub pose **open**;
      `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose open iphone-duo`
      reports every size accepted; `7-duo-inner-landscape/` files are 2853 × 2007.
- [ ] Inner shots render the **standard** 40-inset layout (not the widened Duo card)
      — confirms `isOuterPortrait` correctly excludes regular/regular.

### Phase 4
- [ ] Simulating a missing runtime (e.g. temporarily point the pattern at a bogus
      name or rename the check) exits non-zero with the runtime hint rather than a
      silent skip. **Restore before committing.**
- [ ] Full three-invocation sweep across all six languages:
      `… --duo-pose folded iphone-duo`, `… --duo-pose book iphone-duo`,
      `… --duo-pose open iphone-duo`; all four class folders are present with every
      size accepted.
- [ ] `--fetch-wallpapers` resolves all five `iphone-duo-*` slots.
- [ ] Full CI-identical gate runs once via the `run-gate` skill (`./scripts/test.sh`).

## Observations for review

- **Push:** the branch was rebased onto `main` (`50718721` an ancestor of HEAD) and
  force-pushed with `--force-with-lease` (`c538cb05`), so PR #250's head is no longer stale.
- **Shellcheck (not gate-wired):** Phase 1 introduced 7 findings in `duo_six_shots` —
  SC2178 on `local display=$2` and 6× SC2128 on `--display "$display"`, confused with
  `shoot`'s `local display=()` array. Cleared in review by renaming the local to
  `screen_id`; `shellcheck -S warning` is now clean (as it already was on `main`).
- **Process note:** the first two Phase 1 subagent launches received an empty task
  (the parent omitted the required `task` field) and each implemented all four phases
  without committing; both were discarded via `git checkout`, and Phase 1 was re-run with
  a correct, single-phase task. The final four commits are clean, one per phase.
