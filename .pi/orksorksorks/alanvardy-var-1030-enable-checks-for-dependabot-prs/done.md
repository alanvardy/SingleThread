# Done

- **Branch / head SHA**: `alanvardy-var-1030-enable-checks-for-dependabot-prs`
  @ `50e9f6ed` (review target; marker commit follows this file). PR #207
  (`gh pr list` → number 207, `OPEN`, `isDraft: true`, author `alanvardy`).
- **Rebase**: no conflicts. Branch was a no-op rebase onto `origin/main`
  (merge-base `74fcd2c6`); working tree clean, `HEAD` == remote.
- **Mechanical checks**: No Swift/app source is touched, so `./scripts/test.sh`
  is deliberately **not** the gate for this change (it never parses workflow
  YAML). The language-appropriate check is `actionlint`:
  - `actionlint` **baseline-compare vs `main`** — identical finding set before
    and after (4 pre-existing `shellcheck SC2086:info` on the
    `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` steps, now at lines
    33/102/160/261). **No new findings.**
  - Gate landed on exactly 6 jobs (`grep -c` → `6`); trigger landed once
    (`grep -c '^  pull_request:$'` → `1`).
  - Diff is one code file, additions only: `.github/workflows/ci.yml | 9 ++`.
    (Branch-vs-main also carries the three `.pi/orksorksorks/<branch>/` QRSPI
    artifacts: `medium.md`, `plan.md`, `implement.md`.)
- **Review outcome**: one bounded fresh-context `reviewer`, no blockers.
  - Angles covered: trigger/gate correctness (short-circuit null-safety on
    `push`, `pull_request.user.login` identity, default activity types),
    security (`pull_request_target` correctly avoided; only
    `secrets.GITHUB_TOKEN`, read-only, already SARIF-disabled `secret-scan`),
    concurrency (`ci-${{ github.ref }}` distinct for `refs/pull/<N>/merge` vs
    `refs/heads/main`), CI cost/blast radius, docs/plan accuracy, AGENTS.md
    conformance.
  - **Fixes applied: none** (no fixes worth doing now). No edits made by the
    reviewer.
  - **Optional improvements noted, not applied** (no `autofix` in the
    invocation; await instruction):
    1. `plan.md` "Blast radius" says "Only `.github/workflows/ci.yml` changes;
       9 added lines" — true for the Phase 1 commit, but branch-vs-main also
       includes the `.pi` artifacts. `implement.md` scopes this correctly;
       reader-facing wording only.
    2. The full macos-26 matrix runs on every weekly workflow-pin PR (intended
       per the ticket; a `paths:` filter was correctly rejected for adding a
       silent-skip failure mode).
- **Deferred / pre-negotiated fallback**: `secret-scan` under Dependabot's
  read-only `GITHUB_TOKEN` cannot be exercised pre-merge (GitHub reads
  PR-event workflow config from the merge ref against `main`). If the first
  post-merge Dependabot PR errors on a token/permission check (not a finding),
  narrow that one job to `github.event_name == 'push'` — do **not** add
  `pull_request_target` or widen `permissions`.
- **Remaining manual items** (from `plan.md` / `implement.md`; CI is
  authoritative and only observable post-push/merge):
  - [ ] **Human-PR exemption** on this ticket's PR #207: one `pull_request`-
        event run appears with all six jobs `skipped`, none started.
  - [ ] **Dependabot-PR path (post-merge)**: first Dependabot PR produces a
        run where all six jobs complete green, `unit-tests` on both matrix
        legs (`iPhone 17`, `iPad (A16)`), including `secret-scan`.
  - [ ] **Push-to-`main` unchanged**: the next `main` commit still produces a
        full `push`-event run.
  - [ ] If checks are ever made required, note human PRs report them
        `skipped` (GitHub treats that as passing) — enforcing them for human
        PRs is a separate ticket.
- **Revert**: one-file revert of commit `81c28914`.