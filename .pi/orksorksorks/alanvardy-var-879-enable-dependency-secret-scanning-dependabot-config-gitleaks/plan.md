# Implementation Plan

## Overview

Add secret scanning (gitleaks in CI), Dependabot dependency updates, and
vulnerability alerts to the SingleThread repo — three committed config files
plus one owner-side `gh api` call, verified by CI green.

---

## Phase 1: Scanner config — `.gitleaks.toml`

### Changes

#### 1. Create `.gitleaks.toml`
**File**: `.gitleaks.toml` (new)
**Action**: create

```toml
[extend]
useDefault = true

[allowlist]
description = "Base64-encoded 1×1 JPEG test fixture — high-entropy but not a credential"
paths = [
    '''SingleThreadTests/BackgroundTestFixtures.swift'''
]
```

**Why**: `useDefault = true` ensures the built-in ~150–200 rules still apply
(custom config would otherwise replace all defaults). The allowlist is
path-scoped to the single known false-positive file, not a blanket directory.
The `'''` (triple-single-quote) literal strings in TOML avoid escaping issues
with the path.

### Verification

#### Automated
- [x] Baseline documented (gitleaks 8.30.1 default rules): `gitleaks detect --no-banner` exits 0 — `BackgroundTestFixtures.swift` does **not** fire with default rules (driver-tested; the base64 JPEG is split across concatenated literals and lacks rule context keywords). The allowlist is kept as **defensive insurance** against future rule changes, not because it currently suppresses a finding
- [x] `gitleaks detect --no-banner` exits 0 **with** `.gitleaks.toml` present (config loads without parse errors)
- [x] `python3 -c "import tomllib; tomllib.load(open('.gitleaks.toml', 'rb'))"` — TOML parse check (note: `'rb'` required — `tomllib.load` mandates binary mode since Python 3.11; the plan's original `open(...)` text-mode form raises `TypeError`)

#### Manual
- [ ] Confirm `gitleaks detect --no-banner --log-level=trace` shows the config is loaded (no parse errors)

---

## Phase 2: CI wiring — `ci.yml` pull_request trigger + secret-scan job

### Changes

#### 1. Add `pull_request` trigger to `on:` block
**File**: `.github/workflows/ci.yml`
**Action**: modify

```yaml
# Change: add pull_request trigger (cross-cutting — affects all existing jobs too)
on:
  push:
    branches: [main]
  pull_request:    # ← NEW
```

**Exact edit** (`ci.yml:3–5`):

Old:
```yaml
on:
  push:
    branches: [main]
```

New:
```yaml
on:
  push:
    branches: [main]
  pull_request:
```

**Why**: Without `pull_request`, the `secret-scan` job (and all existing jobs)
would only run post-merge on `main` — useful for audit but not for blocking
secrets pre-merge. The existing `concurrency` group
(`ci-${{ github.ref }}`, `cancel-in-progress: true` at `ci.yml:7–9`) handles
the double-run when both `push` and `pull_request` events fire on a PR branch.

#### 2. Append `secret-scan` job
**File**: `.github/workflows/ci.yml`
**Action**: append after the last existing job (`watch-ui-tests`, ending at
`-only-testing:SingleThreadWatchTests`)

```yaml
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: gitleaks/gitleaks-action@v2
        env:
          GITLEAKS_VERSION: "8.30.1"
```

**Why**:
- `ubuntu-latest` — avoids burning macOS minutes on a linux-native binary
- `fetch-depth: 0` — full history so gitleaks scans the entire commit range,
  not just the tip
- `gitleaks/gitleaks-action@v2` — major-tag pinning, matching the repo's
  convention (`checkout@v4`, `setup-xcode@v1`, `cache@v4`)
- `GITLEAKS_VERSION: "8.30.1"` — env-pinned binary version; the action already
  passes `--exit-code=2` by default
- No `needs:` — independent parallel job (consistent with the 5 existing jobs)
- No `permissions:` block — implicit default token is sufficient; no SARIF
  upload to code scanning

### Verification

#### Automated
- [x] `actionlint .github/workflows/ci.yml` — clean with zero new findings from this phase; exit 0 when the 4 pre-existing SC2086 info-level warnings (unquoted `$GITHUB_ENV` on unchanged lines, present identically on origin/main) are excluded (`-shellcheck ""`); no CI impact (workflow does not run actionlint)
- [x] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` — YAML parse check
- [x] `grep -c 'pull_request:' .github/workflows/ci.yml` returns ≥ 1
- [x] `grep -c 'secret-scan:' .github/workflows/ci.yml` returns ≥ 1
- [x] `grep -A1 'secret-scan:' .github/workflows/ci.yml | grep 'ubuntu-latest'` — confirms runner
- [x] `grep 'needs:' .github/workflows/ci.yml` returns nothing (confirm no `needs:` anywhere, matching existing convention)

#### Manual
- [ ] Push to PR branch, confirm `secret-scan` job appears in the CI checks and runs independently in parallel
- [ ] Confirm `secret-scan` job exits green on the PR (gitleaks passes with `.gitleaks.toml`)

---

## Phase 3: Dependabot config — `.github/dependabot.yml`

### Changes

#### 1. Create `.github/dependabot.yml`
**File**: `.github/dependabot.yml` (new)
**Action**: create

```yaml
version: 2
updates:
  - package-ecosystem: swift
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "08:00"
      timezone: America/Vancouver
    reviewers:
      - "alanvardy"
    open-pull-requests-limit: 5

  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "08:00"
      timezone: America/Vancouver
    reviewers:
      - "alanvardy"
    open-pull-requests-limit: 5
```

**Why**:
- `swift` — SPM packages resolved via `Package.resolved` at repo root
- `github-actions` — workflows at `.github/workflows/`, `directory: "/"` covers them
- `reviewers: ["alanvardy"]` — plain username; personal account has no org
  teams. Must be a collaborator (alanvardy is the sole owner)
- `open-pull-requests-limit: 5` — explicit (matches default; self-documenting)
- `schedule`: Monday 08:00 PT — predictable, out-of-band with active
  development hours
- No `assignees` — reviewer alone suffices for a single-author repo

### Verification

#### Automated
- [x] `python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))"` — YAML parse check
- [x] Schema check via manual inspection: `version: 2`, both `updates[]` blocks have `package-ecosystem`, `directory`, `schedule.interval`, `schedule.day`, `reviewers`
- [x] `grep '"alanvardy"' .github/dependabot.yml` — confirm reviewer is plain username, not org/team slug
- [x] `grep 'open-pull-requests-limit: 5' .github/dependabot.yml` — explicit limit present

#### Manual
- [ ] Post-merge observation: Dependabot opens PRs on the next Monday 08:00 PT (not a blocking checkpoint; document in PR description as a post-merge verification)

---

## Phase 4: Vulnerability alerts enablement

### Changes

#### 1. Enable vulnerability alerts via `gh api`
**File**: none (no committed file)
**Action**: execute once as repo owner

```bash
# Enable
gh api -X PUT repos/alanvardy/SingleThread/vulnerability-alerts

# Verify
gh api repos/alanvardy/SingleThread/vulnerability-alerts
```

**Why**: Vulnerability alerts are currently disabled (GET returns 404).
Secret scanning and push protection are already enabled — this is the only
remaining security-analysis toggle. This is a one-time owner action; not a
committed file.

### Verification

#### Automated (CLI-based)
- [x] `gh api -X PUT repos/alanvardy/SingleThread/vulnerability-alerts` returns HTTP 204 (or 200 with `{"enabled":true}`)
- [x] `gh api repos/alanvardy/SingleThread/vulnerability-alerts` returns HTTP 200 with `enabled: true` (previously 404 "Vulnerability alerts are disabled")

#### Manual
- [ ] Document the before/after state in the PR description (this is the one artifact that can't be reviewed in a diff)

---

## Final Verification

- [ ] All files committed: `.gitleaks.toml`, `.github/dependabot.yml`, `.github/workflows/ci.yml`
- [ ] `./scripts/test.sh` passes (full CI-identical Swift gate — config-only changes; this is a no-op regression check)
- [ ] PR is ready for review with all checkboxes above ticked

---

## Phase Dependencies

```
Phase 1 (.gitleaks.toml) ──→ Phase 2 (ci.yml secret-scan job)
                                      │
Phase 3 (dependabot.yml) ────────────┤ (independent, can run in parallel)
                                      │
Phase 4 (vulnerability alerts) ──────┘ (independent, can run in parallel)
```

Phases 1→2 must be sequential (the CI job needs the config to pass). Phases 3
and 4 are independent of the gitleaks stack and of each other — they can be
sequenced in any order after Phase 2, or run in parallel.

## Implementation Order

1. **Phase 1** — Create `.gitleaks.toml`, verify locally with `gitleaks detect`
2. **Phase 2** — Edit `ci.yml` (add `pull_request` trigger + `secret-scan` job), commit, push, verify CI green
3. **Phase 3** — Create `.github/dependabot.yml`, verify YAML parse + schema
4. **Phase 4** — Execute `gh api` command, verify 204 + GET `enabled: true`
5. **Commit + push final** — Run full gate (`./scripts/test.sh`), open PR