# Task

VAR-1030 — Enable GitHub Actions checks for Dependabot pull requests **only**, while keeping every other PR exempt from checks.

Context: `.github/workflows/ci.yml` currently triggers solely on `push` to `main`, so Dependabot PRs (`.github/dependabot.yml` is already active — this is a follow-on to VAR-879) get no CI signal until merge. The change must add CI checks for Dependabot PRs without bringing in checks for human/internal PRs.

Build: amend `.github/workflows/ci.yml` (the single workflow file — the whole change lives here) so Dependabot PRs run the existing checks, and explicitly verify no other PR events trigger them. The known trap: naively adding `pull_request` to `on:` enables checks for **all** PRs, which is exactly what we don't want.

Design space to settle in the plan step (no research fan-out needed — standard GitHub Actions territory):
- Trigger choice: `pull_request` vs `pull_request_target` (Dependabot's branches live in the base repo, so a gated `pull_request` is viable and safer; consider whether `GITHUB_TOKEN`-only jobs like gitleaks need target semantics).
- Gating mechanism: job-level `if: github.event_name != 'pull_request' || github.actor == 'dependabot[bot]'` (or equivalent) so only Dependabot-actor PR events run the gate; note the workflow-level `concurrency` key may also need to key off the PR ref so Dependabot PR runs don't cancel `main` pushes and vice versa.
- Verify against the repo's human-PR workflow: today all changes go through PRs (never direct pushes to main per AGENTS.md), so confirm the chosen gate keeps those PRs check-free while Dependabot PRs get the full gate.

Deliverable: a reviewable `ci.yml` diff plus a short verification plan (CI is authoritative for an Actions trigger change; no unit tests apply — this is workflow config, not app code). Do not touch `.github/dependabot.yml` or any repo settings unless the plan step uncovers a hard blocker; note branch-protection/status-check implications in the plan instead.

## Why MEDIUM

Breadth: shared build/CI **convention code** (`.github/workflows/ci.yml`) is the whole change surface — a wrong trigger edit silently enables checks on all PRs, so it needs a plan step + one human gate. M1 holds (0–2 unknowns, standard GitHub Actions pattern); not LARGE — single file, no schema, no new subsystem, no cross-cutting, no research fan-out. Not SMALL — fails SMALL D (shared/convention build config) and E (the trigger-gating mechanism is a design decision), and there is no existing PR-trigger pattern in this repo to copy.

## Key files (from recon)

- `.github/workflows/ci.yml` — the only file that should change; currently `on: push` only, with jobs `unit-tests`, `ui-tests-smoke`, `mac-tests`, `lint`, `watch-ui-tests`, `secret-scan` and a workflow-level `concurrency` block keyed on `github.ref`.
- Context only: `.github/dependabot.yml` (already active, don't change), `.gitleaks.toml`, prior ticket VAR-879 artifacts under `.pi/orksorksorks/alanvardy-var-879-enable-dependency-secret-scanning-dependabot-config-gitleaks/`.