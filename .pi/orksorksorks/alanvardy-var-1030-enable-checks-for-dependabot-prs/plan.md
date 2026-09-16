# Implementation Plan

## Overview

Amend `.github/workflows/ci.yml` — the **only** file that changes — to add a
`pull_request` trigger gated at the job level so that only Dependabot-authored
PRs run the six existing jobs, while push-to-`main` behaviour is unchanged.
This is a **single phase** by design: the trigger and the gate must land in the
same commit, because adding `pull_request` before the gates exist opens a window
in which every human PR runs the full CI gate — the exact trap this ticket
exists to avoid.

### Decisions settled in recon (with rationale)

| Decision | Chosen | Why | Rejected |
|---|---|---|---|
| Trigger event | `pull_request`, gated | Dependabot branches live in the base repo (`dependabot.yml` sets no `target-branch`; only ecosystem is `github-actions`), so plain `pull_request` reaches them. | `pull_request_target` — runs the base config but checks out PR code (the standard RCE footgun), and is only needed to hand secrets to PR code. The one token consumer is `secret-scan`, which uses `secrets.GITHUB_TOKEN`, always provided. |
| Gate expression | `github.event_name != 'pull_request' \|\| github.event.pull_request.user.login == 'dependabot[bot]'` | Keys off the PR **author** (stable for the PR's whole life) and `!= 'pull_request'` (a future `schedule`/`workflow_dispatch` trigger is not silently gated). | `github.actor` — changes to whoever pushed to the branch last, so a maintainer push to a Dependabot branch would silently drop checks; `== 'push'` — over-narrow. |
| `branches:` filter under `pull_request:` | none | Unfiltered cannot silently skip a Dependabot PR if `dependabot.yml` ever gains `target-branch`; human PRs are still exempt via the job gate. | `branches: [main]` — mirrors the `push` trigger but adds a silent-skip failure mode. |
| `concurrency:` | unchanged | `group: ci-${{ github.ref }}` already resolves to `refs/pull/<N>/merge` on PR events vs `refs/heads/main` on push, so Dependabot PR runs and `main` pushes occupy different groups and cannot cancel each other. | Keying the group on the PR number — no benefit, larger diff. |
| `secret-scan` gate | same as every other job | It is a normal job; the token is `GITHUB_TOKEN` (not a repo secret), and it needs no fork-only privilege. | Exempting/skip-gating it up front — would silently lose the scan on the PRs that change pinned action SHAs. |

### Accepted trade-off (documented, not fixed)

A job-level `if:` cannot suppress the *workflow run* itself — GitHub Actions has
no conditional trigger. Human PRs will therefore show a `CI` run whose jobs are
all `skipped` (grey, zero runner minutes). The only alternative is a repo-settings
change, which `medium.md` puts out of scope.

### Blast radius

- Within the Phase 1 code commit, only `.github/workflows/ci.yml` changes: 9 added lines, 0 removed (validated this session against `HEAD`). The branch as a whole also carries the `.pi/orksorksorks/<branch>/` QRSPI artifacts (`medium.md`, `plan.md`, `implement.md`), which are pipeline docs, not code.
- No schema, no migration, no new dependency, no `.github/dependabot.yml` change, no repo-settings change.
- `repos/alanvardy/SingleThread` is **public** with **no branch protection on `main`** (verified this session: `gh api repos/alanvardy/SingleThread/branches/main/protection` → `404 Branch not protected`), so no required-status-check interaction exists today.
- No app/Swift source is touched, so the project's `./scripts/test.sh` pipeline is deliberately not the gate for this change (see Phase 1 verification).

---

## Phase 1: Gated `pull_request` trigger for Dependabot PRs only

### Changes

#### 1. Add the gated `pull_request` trigger
**File**: `.github/workflows/ci.yml`
**Action**: modify

Current (ci.yml:3–5):

```yaml
on:
  push:
    branches: [main]
```

End state:

```yaml
on:
  push:
    branches: [main]
  # Dependabot PRs only. A plain pull_request trigger would enable checks on
  # every PR; the gate lives in the `if:` on each job below.
  pull_request:
```

#### 2. Gate each of the six jobs
**File**: `.github/workflows/ci.yml`
**Action**: modify

Insert one identical line as the **first child key of every job** (immediately
after the job name, before `runs-on:` / `strategy:` / `permissions:`):

```yaml
    if: github.event_name != 'pull_request' || github.event.pull_request.user.login == 'dependabot[bot]'
```

Jobs to touch, by their **pre-change** line numbers:

- `unit-tests:` (ci.yml:12)
- `ui-tests-smoke:` (ci.yml:80)
- `mac-tests:` (ci.yml:141)
- `lint:` (ci.yml:193)
- `watch-ui-tests:` (ci.yml:240)
- `secret-scan:` (ci.yml:311)

Result, first job as the pattern:

```yaml
jobs:
  unit-tests:
    if: github.event_name != 'pull_request' || github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: macos-26
    strategy:
      matrix:
        device: ["iPhone 17", "iPad (A16)"]
```

and the one job that also carries a `permissions:` block:

```yaml
  secret-scan:
    if: github.event_name != 'pull_request' || github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: ubuntu-latest
    permissions:
      contents: read
```

Change nothing else: no `branches:` filter, no `concurrency` edit, no
`permissions` edit, no job bodies, no other file. **Validated this session**:
the exact snippets above, applied to a scratch copy of `ci.yml`, produce no new
`actionlint` findings.

### Verification

#### Automated

- [x] `actionlint` reports **no new findings** — baseline-compare, because `ci.yml` already carries 4 pre-existing `shellcheck SC2086` findings (ci.yml:33, 102, 160, 261) and `actionlint` already exits non-zero *before* this change:
  ```bash
  git show HEAD:.github/workflows/ci.yml > /tmp/ci-before.yml
  actionlint /tmp/ci-before.yml 2>&1 | sed 's#^/tmp/ci-before.yml##' | sort > /tmp/find-before.txt
  actionlint .github/workflows/ci.yml 2>&1 | sed "s#^$(pwd)/##" | sort > /tmp/find-after.txt
  diff /tmp/find-before.txt /tmp/find-after.txt
  ```
  Pass condition: `diff` prints nothing. (Validated this session: identical findings, before and after.)
- [x] The gate landed on exactly six jobs — must print `6`:
  ```bash
  grep -c "github.event.pull_request.user.login == 'dependabot\[bot\]'" .github/workflows/ci.yml
  ```
- [x] The trigger landed exactly once, under `on:` — must print `1`:
  ```bash
  grep -c '^  pull_request:$' .github/workflows/ci.yml
  ```
- [x] The diff is one file, additions only:
  ```bash
  git diff --stat && git status --porcelain
  ```
  Pass condition: exactly `.github/workflows/ci.yml`, `1 file changed, 9 insertions(+)`, and `git status --porcelain` lists no other modified path.
- [ ] `./scripts/test.sh` is deliberately **not** the gate for this phase: nothing but `.github/workflows/ci.yml` changes, no Swift source is touched, and `test.sh` never parses workflow YAML, so none of its iOS / watch / macOS stages can observe a GitHub trigger. Say this in the PR body rather than staying silent.

#### Manual

- [ ] **Human-PR exemption (red-first, observed in CI on this ticket's PR).** This ticket's own PR #207 is the human-PR test case.
  1. Before pushing the change: `gh run list --workflow ci.yml --branch alanvardy-var-1030-enable-checks-for-dependabot-prs` → no `pull_request`-event run exists at all.
  2. After pushing: one run appears with event `pull_request` in which all six jobs are `skipped`, and `gh run view <run-id>` shows no job started. This is what proves the *gate* (not the trigger) exempts human PRs.
- [ ] **Dependabot-PR path — post-merge only.** PR-event workflow config is read from the PR's merge ref and Dependabot PRs are raised against `main`, so this cannot be observed before merge.
  1. `gh pr list --author 'app/dependabot' --state open`; if none is open, comment `@dependabot recreate` on a Dependabot PR or wait for the weekly Monday 08:00 America/Vancouver run (`.github/dependabot.yml`).
  2. `gh run list --workflow ci.yml --event pull_request` → a run on that PR where all six jobs run to completion, `unit-tests` on both matrix legs (`iPhone 17`, `iPad (A16)`).
- [ ] **Push-to-`main` unchanged**: the next commit to `main` produces a full CI run with event `push`.
- [ ] **Fallback if `secret-scan` fails on Dependabot PRs only** (Dependabot-triggered `pull_request` runs get a read-only `GITHUB_TOKEN`, as fork PRs do): if gitleaks-action errors on a token/permission check rather than on a finding, narrow that one job's condition to `github.event_name == 'push'` so the scan stays on `main` pushes, and record the reason in the PR body. Do **not** add `pull_request_target` and do **not** broaden `permissions` to `write`.

---

## Post-merge notes to record in the PR body

- Rendering names of the checks are the six jobs matrix-expanded, e.g. `unit-tests (iPhone 17)`, `unit-tests (iPad (A16))`, `ui-tests-smoke (iPhone 17)`, `mac-tests`, `lint`, `watch-ui-tests`, `secret-scan`.
- `main` has no branch protection today, so nothing consumes those names yet. If they are later made required checks, note that human PRs report them as `skipped`; GitHub treats `skipped`/`neutral` as passing for branch protection, so the requirement would be inert for human PRs — enforcing them for human PRs is a separate decision (and a separate ticket), not this change.
- Reverting is a one-file revert of the single Phase 1 commit.
