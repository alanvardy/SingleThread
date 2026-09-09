# Design Discussion

## Current State

The SingleThread repo has **no dependency scanning, no secret scanning in CI, and
no dependabot configuration** (`research.md` Q3). Specifically:

- `.github/` contains only `ci.yml` (5 parallel macOS jobs, push-to-main trigger
  only, no `pull_request` trigger — `ci.yml:3–5`). No `dependabot.yml`, no
  `CODEOWNERS`, no `SECURITY.md` (`research.md` Q3).
- Vulnerability alerts are **disabled** at the repo level (HTTP 404 from
  `GET /repos/alanvardy/SingleThread/vulnerability-alerts` — `research.md` Q3).
  Secret scanning and push protection are already **enabled** (`research.md` Q3).
- The only scanner-significant fixture is the base64 1×1 JPEG in
  `SingleThreadTests/BackgroundTestFixtures.swift:8–20` (~2,700 chars of
  high-entropy base64 across 12 concatenated string literals). No existing
  allowlist/ignore markers anywhere in the tree (`research.md` Q2).
- CI pins third-party actions by major tag only: `checkout@v4`, `setup-xcode@v1`,
  `cache@v4` (`ci.yml:21,23,31`). No SHA pinning. The sibling `alanvardy/api`
  repo SHA-pins CodeQL at `github/codeql-action@v4.37.9` but has a dormant
  (unused) `.github/workflows/gitleaks/gitleaks.toml` (`research.md` Q5).
- `alanvardy` is a **personal account** — no GitHub teams exist
  (`orgs/alanvardy/teams` → 404). Dependabot reviewers can only be the plain
  username `alanvardy` (`research.md` Q5).
- Branch HEAD `60ee183` adds only a `DELETEME` stub; no implementation exists
  (`research.md` Q3).

## Desired End State

Three committed files + one owner-side setting change, verified by the full CI
gate (`./scripts/test.sh`):

1. **`.github/dependabot.yml`** — weekly swift + github-actions updates,
   reviewer `alanvardy`, no assignees, limit 5 open PRs per ecosystem.
2. **`.github/workflows/ci.yml`** — new `secret-scan` job (ubuntu, independent,
   parallel) running gitleaks v8.30.1 with `--exit-code=2`, plus a `pull_request`
   trigger added to the workflow so the scan blocks PRs pre-merge.
3. **`.gitleaks.toml`** — extends defaults, path-allowlists the base64 JPEG
   fixture. Narrowest scope; widened only after a dry run during planning
   confirms any additional fixtures fire.
4. **Vulnerability alerts enabled** — owner action via
   `gh api -X PUT repos/alanvardy/SingleThread/vulnerability-alerts`
   (not a committed file; executed once and verified).

Verification: the `secret-scan` job passes green on the PR branch, dependabot
config is valid YAML, and `vulnerability-alerts` returns HTTP 204.

## Patterns to Follow

| Pattern | Source | Apply to |
|---|---|---|
| Major-tag action pinning (`checkout@v4`, `setup-xcode@v1`) | `ci.yml:21,23,31` | gitleaks action (`gitleaks/gitleaks-action@v2`), dependabot (N/A — native GitHub) |
| Independent parallel jobs, no `needs:` | `ci.yml:13,81,142,194,241` | `secret-scan` job — no dependency on macOS builds |
| `runs-on: ubuntu-latest` for non-Apple tooling | (not in repo yet; industry convention) | `secret-scan` — avoid burning macOS minutes on a linux-native binary |
| `[extend] useDefault = true` in tool configs | `alanvardy/api` dormant `.github/workflows/gitleaks/gitleaks.toml` (`research.md` Q5) | `.gitleaks.toml` |
| Test fixture paths explicitly scoped, not blanket-dir allowlisted | `research.md` Q2 — only one fixture fires | `.gitleaks.toml` `[allowlist] paths` |
| CI inlines its own commands (does not call `scripts/test.sh`/Makefile) | `research.md` Q1/Q4 | `secret-scan` step — inlined in `ci.yml` |

### Patterns to AVOID

- **SHA-pinning gitleaks action** — the repo's convention is major-tag for
  `actions/*` and `maxim-lobanov/setup-xcode@v1`. SHA-pinning would be
  inconsistent and provides marginal benefit when the binary version is pinned
  via `GITLEAKS_VERSION`.
- **Blanket test-directory allowlist** (`SingleThreadTests/**` or
  `SingleThreadWatchTests/**`) — defeats the purpose of the scanner; a real
  secret in a test fixture must be caught.
- **Inline `gitleaks:allow` comments** in Swift source — pollutes production
  code with scanner-specific markers.

## Design Decisions

1. **Gitleaks integration**: `gitleaks/gitleaks-action@v2` with
   `GITLEAKS_VERSION: 8.30.1` env pin, `fetch-depth: 0`, `--exit-code=2`.
   Blocking CI step only — no SARIF upload to code scanning (keeps the surface
   minimal; SARIF upload adds `github/codeql-action/upload-sarif@v3` and a
   GitHub Advanced Security dependency that a personal-account repo may not
   need).

2. **Allowlist mechanism**: Repo-root `.gitleaks.toml` with
   `[extend] useDefault = true` and path-scoped `[allowlist] paths` for
   `SingleThreadTests/BackgroundTestFixtures.swift`. Self-documenting, survives
   line moves, and matches the `alanvardy/api` convention of a repo-level
   gitleaks config. Path-scoped to the one known fixture; a dry run during
   planning confirms whether anything else fires.

3. **Allowlist scope**: Narrow — only the base64 JPEG file. If the dry run
   shows additional false positives from the `--seed` JSON launch args or
   unsplash URLs, widen only to those specific paths. Never blanket-allowlist
   entire test directories.

4. **CI job placement**: New independent `secret-scan` job on `ubuntu-latest`,
   parallel to the 5 existing macOS jobs. No `needs:` — gitleaks needs no
   Xcode, no simulator, no build artifacts. Fast (< 30s), zero macOS minutes.

5. **CI trigger**: Add `pull_request` to the workflow's `on:` block (currently
   `push` to `main` only). Without this, gitleaks would only fire post-merge —
   useful for audit but not for blocking secrets pre-merge. The existing jobs
   are harmless on PRs (they just run). This is a one-line change to `ci.yml:3–5`.

6. **Dependabot reviewers**: `["alanvardy"]` (plain username, no assignees).
   Forced by the personal-account constraint — no org teams exist. Reviewer
   must be a collaborator; `alanvardy` is the sole owner/collaborator.

7. **Dependabot schedule**: `interval: weekly`, `day: monday`, `time: "08:00"`,
   `timezone: America/Vancouver`. `open-pull-requests-limit: 5` (default).
   Ecosystems: `swift` (directory `/`) and `github-actions` (directory `/`).

8. **Vulnerability alerts enablement**: One-time owner action
   (`gh api -X PUT repos/alanvardy/SingleThread/vulnerability-alerts`),
   executed during implementation and verified with
   `gh api repos/alanvardy/SingleThread/vulnerability-alerts` (expects 204).
   Not a committed file. Secret scanning + push protection are already enabled
   — no action needed.

## What We're NOT Doing

- **Not adding a SARIF upload to code scanning** — out of scope; the blocking
  `--exit-code=2` CI step is sufficient for this ticket.
- **Not adding CODEOWNERS or SECURITY.md** — the task doesn't ask for them, and
  there's no team structure to encode in CODEOWNERS.
- **Not modifying `scripts/test.sh` or the Makefile** — gitleaks runs in CI
  only, inline in `ci.yml`, matching the existing CI pattern.
- **Not changing the existing 5 macOS jobs** — the `secret-scan` job is
  additive only; no `needs:` wiring, no permissions changes to existing jobs.
- **Not adding `.env*` to `.gitignore`** — no `.env` file exists, and the task
  doesn't ask for env-handling conventions.
- **Not running gitleaks in pre-commit hooks or locally** — CI-only for this
  ticket.
- **Not pinning third-party actions by SHA** — the repo's major-tag convention
  is consistent and sufficient for this scope.

## Open Risks

1. **Dry run may reveal additional false positives** — the JSON `--seed` launch
   args and unsplash URLs are low-entropy, but gitleaks' `generic-api-key` rule
   uses keyword+entropy heuristics that could misfire. Mitigation: run `gitleaks
   detect` during planning; widen allowlist only for confirmed false positives.
2. **`pull_request` trigger may double-run on `push` to PR branches** — if the
   PR branch is pushed to and a PR exists, both `push` and `pull_request`
   events fire. Mitigation: the existing `concurrency` group
   (`ci-${{ github.ref }}`, `ci.yml:7–9`) with `cancel-in-progress: true` will
   cancel the stale run. Acceptable.
3. **Dependabot `reviewers` field deprecation** — GitHub has signalled
   `reviewers`/`assignees` may be phased out in favor of CODEOWNERS
   (`research.md` Q5). If the field stops working, the dependabot PRs will
   still open; they just won't auto-assign a reviewer. Mitigation: low-impact
   on a single-author repo; revisit if GitHub removes the field.
4. **`gitleaks/gitleaks-action@v2` SARIF artifact-upload race** — some v2
   releases skip artifact upload when no leaks are found (`research.md` Q5).
   Mitigation: not relying on SARIF artifacts; the blocking exit code is the
   gate.
5. **Vulnerability alerts enablement is a one-time owner action** — cannot be
   committed or reviewed in a PR diff. Mitigation: execute and verify during
   implementation; document the before/after state in the PR description.