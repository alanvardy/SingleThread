# Done

- **Branch / head SHA**: `alanvardy-var-879-enable-dependency-secret-scanning-dependabot-config-gitleaks` / `242348c1`
- **Mechanical checks**: YAML parse ✅ (ci.yml, dependabot.yml), TOML parse ✅ (.gitleaks.toml), actionlint exit 0 (4 pre-existing SC2086 info warnings on unchanged lines), trailing newlines ✅
- **Review outcome**: 5 reviewers + parent scan → 1 blocker fixed (DELETEME removed), 5 fixes worth doing now applied, 4 optional improvements applied, history squash deferred
- **Applied fix commit** (`242348c1`):
  - Removed stray `DELETEME` marker (already removed from main in `ba7d305e`)
  - Dropped non-functional `swift` Dependabot entry (no `Package.swift` at `/`, no `Package.resolved`, zero remote SPM deps); kept `github-actions` only
  - SHA-pinned `gitleaks/gitleaks-action` to `dcedce4` (v2), replacing major-tag reference
  - Added job-level `permissions: contents: read` to `secret-scan` (least-privilege `GITHUB_TOKEN`)
  - Explicitly disabled SARIF upload (`GITLEAKS_ENABLE_UPLOAD_SARIF: false`) with comment; findings gate via exit code 2 in job log
  - Anchored `.gitleaks.toml` allowlist regex with `^…\.swift$` anchors; added defensive-insurance comment
  - Added `GITLEAKS_VERSION` pin comment (Dependabot tracks the action but not the binary version env)
  - Appended trailing newlines to `.github/dependabot.yml` and `.gitleaks.toml`
  - Enabled Dependabot automated security fixes via `gh api -X PUT /repos/alanvardy/SingleThread/automated-security-fixes` → `{"enabled":true}`
  - Corrected `plan.md` Phase 2 concurrency rationale (ci-`${{ github.ref }}` does not de-dupe push vs PR — they have different refs; this only works because `push` is restricted to `[main]`)

## Deferred to owner

- **Commit history — optional interactive rebase**: `a954d702` ("Enable dependency + secret scanning") has a misleading subject (its content was only DELETEME, now removed). `a5b326d7` ("Phase 2 fix") is out of order (committed after Phase 3). Consider squashing `a5b326d7` into `87482997` and dropping/rewording `a954d702` before merge. `main` merges with `--rebase`, so branch history is preserved as-is into main.

## Remaining manual items

- [ ] Confirm `secret-scan` CI job still green on PR #185 after force-push (SHA-pinned action, new `permissions:` block, SARIF-off env)
- [ ] Post-merge observation: Dependabot opens `github-actions` PRs on the next Monday 08:00 PT
- [ ] Verify Dependabot security updates produce automated remediation PRs (not just vulnerability alerts) — enabled via `gh api` above; observe on the first Dependabot PR