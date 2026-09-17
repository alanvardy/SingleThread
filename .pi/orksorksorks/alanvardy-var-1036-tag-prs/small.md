# Task

Ensure **alanvardy is tagged as reviewer on all Dependabot PRs** in the
`alanvardy/SingleThread` repo (Linear VAR-1036).

Investigation at branch start shows this is likely **already satisfied** —
verify, gap-fill if needed, and close:

- `.github/dependabot.yml` on `origin/main` already declares
  `reviewers: ["alanvardy"]` for the `github-actions` ecosystem (the only
  ecosystem Dependabot supports here — Swift has no Dependabot ecosystem).
- All 4 currently-open Dependabot PRs (`gh pr list --repo
  alanvardy/SingleThread --author "app/dependabot" --state open --json
  number,reviewRequests`) already have `alanvardy` in `reviewRequests`.
- `ci.yml` already has a gated `pull_request` trigger for Dependabot-pr-only
  runs (prior ticket VAR-1030, merged PR #207).

Work, in order:
1. Re-verify `reviewers: ["alanvardy"]` is present and covers every
   Dependabot-managed entry in `.github/dependabot.yml`.
2. Check for any open Dependabot PR **missing** the reviewer request
   (Dependabot's `reviewers` key only applies to newly created PRs; an
   older PR can lack it). If any exists, tag it with
   `gh pr edit <n> --add-reviewer alanvardy --repo alanvardy/SingleThread`.
3. If (1) and (2) come back clean, there is **no code change**: record that
   the task is already complete and close the ticket — do not invent work or
   edit `ci.yml`.

No Swift/app sources are touched, so `./scripts/test.sh` is not the gate; the
language-appropriate check is `actionlint` (baseline-compare vs `main`, as
VAR-1030's `done.md` documents) — see its artifact under
`.pi/orksorksorks/alanvardy-var-1030-enable-checks-for-dependabot-prs/`.

## Why SMALL
Single module (`.github/`), ≤2 files, existing pattern already in place; the
only action is verify-and-gap-fill. 0–2 unknowns, no schema change, no new
subsystem or shared/convention code, no design decision or sign-off, and no
test surface (GitHub automation config is verified with actionlint/`gh pr
list`, not unit tests).

## Key files
- `.github/dependabot.yml` — reviewers config (already present on `main`)
- `.github/workflows/ci.yml` — prior VAR-1030 gated Dependabot trigger
  (do not touch unless a genuine gap is found)