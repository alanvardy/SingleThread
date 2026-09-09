# Structure Outline

## Approach

Three committed config files + one owner-side `gh api` call, stacked bottom-up
so each layer is independently verified before the next begins. The gitleaks
stack (config → CI) is the core horizontal pipeline; dependabot and
vulnerability alerts are independent config surfaces that land after the
scanner pipeline is proven green.

---

## Stage 1: Scanner config foundation — `.gitleaks.toml`

**What**: Extends gitleaks built-in defaults with a narrow, path-scoped
allowlist for the one known false positive (the base64 1×1 JPEG fixture in
`SingleThreadTests/BackgroundTestFixtures.swift:8–20`). No blanket directory
allowlists, no inline `gitleaks:allow` comments in source. This config is the
single source of truth consumed by Stage 2's CI job (and any future gitleaks
invocation).

**Files**:
- `.gitleaks.toml` (new)

**Key changes**:
```toml
[extend]
useDefault = true

[allowlist]
description = "Base64-encoded 1×1 JPEG test fixture — high-entropy but not a credential"
paths = [
    '''SingleThreadTests/BackgroundTestFixtures.swift'''
]
```
- `[extend] useDefault = true` — prevents the "custom config replaces all defaults" trap
- Path-scoped to one file (not `SingleThreadTests/**`); research Q2 confirmed no other scanner-significant artifacts exist in the tree

**Tests** (one-time dry run, not a permanent local tool):
1. **Sad-path reproducer**: `gitleaks detect --no-banner` without config → exit 2, output shows `BackgroundTestFixtures.swift` as the only leak
2. **Happy-path**: `gitleaks detect --no-banner` with `.gitleaks.toml` → exit 0 clean, no leaks

**Verify**: `gitleaks detect --no-banner` exits 0 with the config present. YAML/TOML parse check (`python3 -c "import tomllib"` or a simple `gitleaks detect --config=.gitleaks.toml --log-level=trace` that parses the file).

---

## Stage 2: CI wiring — `ci.yml` secret-scan job + `pull_request` trigger

**What**: Adds a new independent `secret-scan` job (ubuntu, parallel to the 5
existing macOS jobs) that runs gitleaks via the official action, pinned to
v8.30.1, consuming the Stage 1 config. Also adds `pull_request` to the
workflow's `on:` block so the scan blocks secrets pre-merge.

**Files**:
- `.github/workflows/ci.yml` (edit)

**Key changes**:

```yaml
# Change: add pull_request trigger (cross-cutting — affects all existing jobs too)
on:
  push:
    branches: [main]
  pull_request:    # ← NEW

# … existing 5 jobs unchanged …

# New job (append after existing jobs, no needs:)
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

- `runs-on: ubuntu-latest` — avoids burning macOS minutes on a linux-native binary
- `fetch-depth: 0` — full history so gitleaks scans the entire commit range, not just the tip
- `gitleaks/gitleaks-action@v2` — major-tag pinning, matching the repo's existing convention (`checkout@v4`, `setup-xcode@v1`)
- `GITLEAKS_VERSION: "8.30.1"` — env-pinned binary version; action already passes `--exit-code=2` by default
- No `needs:` — independent parallel job
- No `permissions:` block — implicit default token is sufficient; no SARIF upload to code scanning

**Cross-cutting note**: The `pull_request` trigger applies to the entire
workflow, not just the new job. The existing 5 macOS jobs will also fire on PR
branches. Mitigation: the existing `concurrency` group
(`ci-${{ github.ref }}`, `cancel-in-progress: true` at `ci.yml:7–9`) handles
double-runs from simultaneous `push` + `pull_request` events — acceptable per
design open risk #2.

**Tests**:
1. YAML validity: `actionlint .github/workflows/ci.yml` (or `python3 -c "import yaml; yaml.safe_load(open('...'))"` as a fallback)
2. Confirm `on:` block contains both `push: [main]` and `pull_request:`
3. Confirm the `secret-scan` job has no `needs:` and runs on `ubuntu-latest`
4. **Real gate**: the `secret-scan` job passes green on the PR branch (CI)

**Verify**: `actionlint` passes; the `secret-scan` CI job is green on the PR.
The `./scripts/test.sh` Swift gate is a no-op regression check for these
config-only edits (the 5 existing macOS CI jobs are the real regression gate,
unchanged).

---

## Stage 3: Dependabot config — `.github/dependabot.yml`

**What**: Configures weekly automated dependency updates for the two ecosystems
(live in the repo) — Swift packages and GitHub Actions — with reviewer
`alanvardy`, no assignees, and a cap of 5 open PRs per ecosystem. Independent
of the gitleaks stack; validated by schema check.

**Files**:
- `.github/dependabot.yml` (new)

**Key changes**:
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

- `reviewers: ["alanvardy"]` — plain username (personal account; no org teams exist — research Q3/Q5)
- No `assignees` — reviewer alone suffices
- `open-pull-requests-limit: 5` — explicit (matches default; self-documenting)
- `directory: "/"` — root for both ecosystems (the repo's only Swift package is at root; workflows at `.github/workflows/`)

**Tests**:
1. YAML validity: `python3 -c "import yaml; yaml.safe_load(open('...'))"`
2. Schema check: `version: 2`, both `updates[]` blocks have `package-ecosystem`, `directory`, `schedule.interval`, `reviewers`
3. `open-pull-requests-limit: 5` (explicit, not relying on default)
4. Live check deferred: dependabot PRs open on the next Monday 08:00 PT — not a blocking checkpoint, documented as a post-merge observation

**Verify**: YAML parse passes; schema fields are complete. Full live verification is post-merge (dependabot opens PRs on schedule).

---

## Stage 4: Vulnerability alerts enablement — owner action

**What**: One-time `gh api` call to enable dependency vulnerability alerts at
the repo level. Not a committed file — executed once, verified, documented in
the PR description. Secret scanning and push protection are already enabled
(research Q3); this is the only remaining security-analysis toggle.

**Files**:
- None (no committed file)

**Key change**:
```bash
# Enable
gh api -X PUT repos/alanvardy/SingleThread/vulnerability-alerts

# Verify
gh api repos/alanvardy/SingleThread/vulnerability-alerts
```

**Tests**:
1. PUT returns HTTP 204 (or 200 with `{"enabled":true}`)
2. GET returns HTTP 200 with `enabled: true` (previously 404 "Vulnerability alerts are disabled")

**Verify**: Both commands succeed. Document before/after state in the PR
description (this is the one artifact that can't be reviewed in a diff — design
open risk #5).

---

## Testing Checkpoints

| After | Must be green | Resume command |
|---|---|---|
| Stage 1 | `gitleaks detect` exits 0 with `.gitleaks.toml` | `gitleaks detect --no-banner` |
| Stage 2 | `actionlint` passes; `secret-scan` CI job green on PR | Push to PR branch, check CI |
| Stage 3 | `dependabot.yml` parses as valid YAML; schema fields complete | `python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))"` |
| Stage 4 | `gh api .../vulnerability-alerts` → 204 / GET → `enabled` | `gh api repos/alanvardy/SingleThread/vulnerability-alerts` |
| Final | `./scripts/test.sh` (Swift gate — no-op regression; config-only changes) | `./scripts/test.sh` via run-gate skill |

**Note**: Stages 3 and 4 are independent of the gitleaks stack (1–2). They can
be sequenced in either order after Stage 2, or run in parallel. The ordering
above places them after the scanner pipeline is proven green so all CI-related
changes are stabilized first.