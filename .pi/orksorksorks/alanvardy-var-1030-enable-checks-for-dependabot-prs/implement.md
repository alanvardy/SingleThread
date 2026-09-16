# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 81c28914 | Gated `pull_request` trigger for Dependabot PRs only |

Branch-hygiene commits (before Phase 1): `155023ff` remove DELETEME bootstrap
marker, `c166d6d6` add design/plan artifacts. Rebase onto `origin/main` was a
no-op (branch was exactly one bootstrap commit ahead).

## Automated Checks

All six Phase 1 checks from `plan.md` run and verified (the parent re-ran the
actionlint baseline-compare, both grep counts, and the diff stat independently):

- [x] `actionlint` reports no new findings — baseline-compare: both before and
      after report the identical 4 pre-existing `SC2086` findings on the four
      `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` steps (post-change lines
      33/102/160/261; the +9 shift is exactly the 9 added lines). Note: the
      plan's literal `sed`-based `diff` prints path/caret noise on this machine
      (`actionlint` renders the `/tmp` file's *resolved relative* path
      `../../../../tmp/ci-before.yml`, which the `sed s#^/tmp/ci-before.yml##`
      cannot strip) — pure rendering noise, zero new findings, verified by
      message-set comparison.
- [x] The gate landed on exactly six jobs — `grep -c` → `6`.
- [x] The trigger landed exactly once, under `on:` — `grep -c '^  pull_request:$'` → `1`.
- [x] The `ci.yml` diff is 9 insertions / 0 deletions, no other file changed
      (`git diff --stat` → `.github/workflows/ci.yml | 9 +++++++++`; the phase
      commit additionally carries the plan.md checkbox bookkeeping, 4 `- [ ]` →
      `- [x]`). Working tree clean after the commit; pushed to origin (fast-forward).
- [x] `./scripts/test.sh` deliberately **not** run as the gate — nothing but
      `.github/workflows/ci.yml` (+ plan.md bookkeeping) changes, no Swift
      source touched, and `test.sh` never parses workflow YAML, so none of its
      iOS / watch / macOS stages can observe a GitHub trigger. State this in
      the PR body rather than staying silent.

## Manual Verification Items (from the plan)

- [ ] **Human-PR exemption (red-first, observed in CI on this ticket's PR).**
      This ticket's own PR #207 is the human-PR test case.
      1. Pre-push baseline: `gh run list --workflow ci.yml --branch alanvardy-var-1030-enable-checks-for-dependabot-prs` → no `pull_request`-event run existed.
      2. Post-push: one run with event `pull_request` in which all six jobs are
         `skipped`, and `gh run view <run-id>` shows no job started — proves the
         *gate* (not the trigger) exempts human PRs.
- [ ] **Dependabot-PR path — post-merge only.** PR-event workflow config is read
      from the PR's merge ref and Dependabot PRs are raised against `main`, so
      this cannot be observed before merge.
      1. `gh pr list --author 'app/dependabot' --state open`; if none, comment
         `@dependabot recreate` on a Dependabot PR or wait for the weekly
         Monday 08:00 America/Vancouver run.
      2. `gh run list --workflow ci.yml --event pull_request` → a run on that
         PR where all six jobs run to completion, `unit-tests` on both matrix
         legs (`iPhone 17`, `iPad (A16)`).
- [ ] **Push-to-`main` unchanged**: the next commit to `main` produces a full CI
      run with event `push`.
- [ ] **Fallback if `secret-scan` fails on Dependabot PRs only** (Dependabot-
      triggered `pull_request` runs get a read-only `GITHUB_TOKEN`, as fork PRs
      do): if gitleaks-action errors on a token/permission check rather than on
      a finding, narrow that one job's condition to `github.event_name == 'push'`
      so the scan stays on `main` pushes, and record the reason in the PR body.
      Do **not** add `pull_request_target` and do **not** broaden `permissions` to `write`.

## Post-merge notes to record in the PR body

- Rendering names of the checks are the six jobs matrix-expanded, e.g.
  `unit-tests (iPhone 17)`, `unit-tests (iPad (A16))`, `ui-tests-smoke
  (iPhone 17)`, `mac-tests`, `lint`, `watch-ui-tests`, `secret-scan`.
- `main` has no branch protection today, so nothing consumes those names yet.
  If they are later made required checks, human PRs report them as `skipped`;
  GitHub treats `skipped`/`neutral` as passing for branch protection, so the
  requirement would be inert for human PRs — enforcing them for human PRs is a
  separate decision (and a separate ticket), not this change.
- Reverting is a one-file revert of the single Phase 1 commit (81c28914).