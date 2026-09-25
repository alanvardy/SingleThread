# Implementation Summary

All four phases of the VAR-1075 test-suite audit were implemented, verified, and committed on
branch `alanvardy-var-1075-test-suite-audit`. The full CI-identical gate has **not** been run yet
— it belongs to review (via the `run-gate` skill) per the plan.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| —     | f6d67795 | Remove bootstrap DELETEME marker (pre-rebase cleanup required before push) |
| 1     | 59df56de | watch Show\*State holder tests |
| 2     | a15b5f7f | extract next-thing widget logic + tests |
| 3     | 90c0095a | AI-sort coordinator trust/fallback tests |
| 4     | 81205b25 | add test-suite audit report |
| 4     | a4886c2a | correct NextThingWidgetLogicTests case name in audit report |

## Automated Checks

- [x] **Phase 1** — four watch `Show*State` suites ran: 16 cases total (4 suites × 4 tests), exit 0; `make watch-build` passes; `make format && make lint` clean. *Note:* the plan's `scripts/test-one.sh SingleThreadWatchTests/…` commands are iOS-scheme-only and cannot drive watch suites, so verification used an equivalent bounded **watch-scheme** invocation (`-scheme SingleThreadWatch -destination 'platform=watchOS Simulator,id=…'`, the `make watch-test`/CI mechanism) — the plan commands as literally written would be a false negative.
- [x] **Phase 2** — `NextThingWidgetLogicTests` ran 4 cases, exit 0; `make build` passes (widget compiles + embeds); `make format && make lint` clean; `make periphery` reports no unused code (neither extracted symbol flagged). Spike passed → extraction performed (not a non-goal).
- [x] **Phase 3** — `AISortCoordinatorTests` runs 20 cases, exit 0 (*plan premised 22 — the file actually had 18 pre-existing `@Test`s; 18 + 2 = 20*); `make lint` clean; `git diff --stat` shows only `AISortCoordinatorTests.swift` (no production code). Two new non-duplicate cases.
- [x] **Phase 4** — `git diff --name-only` shows only `audit-report.md` (no source diff); every non-goal/finding in the report cites a verified path.

## Manual Verification Items (from the plan)

- [ ] **P1** Confirm each of the four watch `Show*State` suites' `@Test` cases are listed in the run output (not filtered to zero). *(Substantively confirmed — the runner reported `totalTestCount == 16` across exactly those suites and fails if ≠ 16 — but flagged for your confirmation.)*
- [ ] **P1** Confirm no `test`-prefixed names survived `make format` (SwiftFormat strips `test` prefixes on unit tests). *(Substantively confirmed: verified the formatted files still carry `unsetKeyDefaultsToOn/Off`, `persistedValueStaysOnInit`, `applyRoundTripsTrueAndFalse`, `applyPersistsToStandardDefaults`.)*
- [ ] **P2** Build + run the iOS app, add the "Next Thing" widget to a simulator home screen, confirm it renders a reminder or the no-access message (unchanged behavior).
- [ ] **P2** Comment out one preference read in `NextThingDisplayPreferences` locally, confirm a unit case fails, then restore — proves the tests bind to the extraction.
- [ ] **P3** Confirm the two new case names do not duplicate existing test names (`rg -n 'func (retries|reRanks)'` → exactly line 516 and 543). *(Substantively confirmed.)*
- [ ] **P4** Report names each non-goal with a rationale (read `audit-report.md` end-to-end).
- [ ] **P4** Run the full CI-identical gate **once** via the `run-gate` skill (`./scripts/test.sh` through the gate subagent — never `nohup`). *(This is the principal remaining gate; run in review.)*
- [ ] **P4** Check `git status` before the phase commit so no `.pi/orksorksorks/` step artifact is folded in besides `audit-report.md`. *(Done at commit time; audit-report.md is the only tracked artifact.)*

## Divergences & Notes

- **Phase 1 verification mechanism**: the plan's `scripts/test-one.sh …SingleThreadWatchTests/…` commands pin the iOS scheme/destination and do not run watch suites; the equivalent watch-scheme invocation (per `make watch-test` / `scripts/test.sh`) was used and passed all four suites.
- **Phase 3 count premise**: plan said "22 cases"; the file had 18 pre-existing cases + 2 added = 20. The two added branches are the intended coverage; no duplicates.
- **Full gate not run**: per the plan, `./scripts/test.sh` runs exactly once after Phases 1–3 commit via the `run-gate` skill at review time.
- The `audit-report.md` deliverable records one user-triage finding (watch `Show*State` `.standard` vs `ShowEnableActionButtonsState` `AppGroup.defaults` persistence divergence) and the explicit non-goals; Phase 4 intentionally made no source change.