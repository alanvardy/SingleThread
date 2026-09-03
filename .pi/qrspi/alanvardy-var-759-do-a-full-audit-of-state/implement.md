# Implementation Summary

VAR-759 — Do a full audit of state. Read-only audit; the work product is the report under
`.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/audit/`. No app code changed.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `2522c15` | Fact base — citation-verified source index (`audit/factbase.tsv`, `verify-citations.sh`, `verify-citations-self-test.sh`) |
| 2     | `b642be1` | Inventory — key-centric and store-mirror cross-reference (`audit/inventory.md`; +9 factbase rows) |
| 3     | `47320ab` + `b16a968` | Combinatorial clusters + cross-target divergence (`audit/clusters.md`, 11-site divergence index; +73 factbase rows; `b16a968` terminates the final row so all 456 citations verify) |
| 4     | `4fab60c` | Enum assessment — 3 sketches + advisory pointers (`audit/enums.md`; +7 factbase rows) |
| 5     | `b0be2a8` | Severity ranking + prioritized action list (`audit/findings.md`, `audit/index.md`; +9 factbase rows) |
| fix   | `bf85c78` | Factbase correction: `authorizationStatus` watch read pinned to blank line 61 → real read at `WatchReminderView.swift:47`; check off final-gate items in plan.md |

> Note: `29b539b` ("docs: point AGENTS.md references…") appeared between Phase 1 and Phase 2 —
> authored and pushed directly by Alan Vardy mid-workflow, not part of this branch's audit work.
> Touches only `AGENTS.md`; no conflict with the audit.

## Automated Checks

- [x] `verify-citations.sh` exits 0 — all 472 pinned `lineText` match source byte-for-byte
- [x] `verify-citations-self-test.sh` exits 0 — deliberate corruption is rejected
- [x] Triplet invariant — all 23 persisted keys have ≥1 declaration + read + write row
- [x] All 23 production keys present in `factbase.tsv` (12 `.standard` + 11 App Group)
- [x] `factbase.tsv` well-formed: header intact, 6 columns, no empty cells (verified via script;
      this also clears the manual "no empty cells" check — the one blank-line row found was fixed)
- [x] Inventory cite-check: all 126 `inventory.md` `*.swift:<line>` refs resolve in `factbase.tsv`
- [x] 23-key split in `inventory.md`: 12 `.standard` keys, 11 App Group keys
- [x] Store mirror table ~50 rows matching research Q2's enumerated stores
- [x] Dual-read-path set = exactly the 12 keys (verified programmatically from the table)
- [x] No `ObservableObject` reference in `inventory.md` (grep = 0)
- [x] Cluster matrices: zero bare `undefined` cells; only the 4 listed open areas
- [x] Every reachable combo's path note resolves in `factbase.tsv` (Phase 3 worker traced each
      `unreachable(proven)` claim against write paths — details in its report)
- [x] All 11 divergence sites carry `file:line` citations resolving in `inventory.md`
- [x] Three enum sketches only; all 8 `replaces` field ids resolve in `factbase.tsv`
- [x] Advisory pointers cover `show*` ×6, dictation, `BackgroundFade`, watch refresh flags
- [x] Findings tier ordering monotonic T1→T2→T3→T4
- [x] Every finding Evidence cites ≥1 `factbase.tsv` entry
- [x] Cluster→finding mapping: completion-transition (T1.1), branch-ordering (T2.2),
      entitlement gate (T4.1), dictation (T1.1)
- [x] Action list items flagged as deferred/separate tickets, not in-scope
- [x] `index.md` links all five artifacts; all files exist
- [x] `./scripts/test.sh` — not re-run (multi-hour); app code is provably untouched
      (`git diff 0dbf963..HEAD` over every app/test/project path = empty), so the gate result is
      unchanged by design

## Manual Verification Items (from the plan)

- [ ] Spot-check 5 random rows: open the file at that line, verify the text matches
- [ ] Check that `audit/factbase.tsv` has no empty cells — **verified by parent script during the
      final gate** (well-formed check passed after fixing the one blank-line row); confirm at leisure
- [ ] Dual-read-path set enumerated in `inventory.md` matches the list (12 keys) — no more, no fewer
- [ ] Store mirror table confirms no `ObservableObject` reference exists — `grep ObservableObject audit/inventory.md` produces no matches — **verified by parent (0 matches)**
- [ ] Every store in the mirror table is `@Observable final class` or explicitly noted as plain class / no view model
- [ ] Walk the completion-transition reachability path: read `WatchReminderViewModel.swift:66-86`, verify the `true,nil` row is correctly proven unreachable — **note:** Phase 3 worker reworded the `false,≠nil` proof (snapshot is taken while flag still false, transient sub-state only); see its report
- [ ] Walk the allSkipped impossibility: read `ReminderStore.swift:138-140`, confirm `allSkipped` requires non-empty reminders
- [ ] Verify widget branch ordering divergence: compare `NextThingWidget.swift:55-95` against `ContentView.swift:355-455` and `WatchReminderView.swift:77-91` (drifted line ranges corrected in `clusters.md`)
- [ ] Spot-check 3 divergence site citations against source
- [ ] Sketch 1 (`CompletionTransition`) adheres to patterns: no persistence needed (transient watch-only), presentation on extension
- [ ] Sketch 2 (`EntitlementGate`) adheres to patterns: `canMutate` computed from enum, single `freemiumCap` constant
- [ ] Sketch 3 (`EmptyState`) mirrors widget's existing `NextThingEntry.State` shape generalized
- [ ] No full enum sketched for advisory-pointer items — pointers only, no case lists
- [ ] Tier definitions are consistent: T1 = data-loss/reachable contradiction, T2 = cross-target divergence, T3 = dual-read drift, T4 = hygiene
- [ ] T4.4 (6 × Show*Preference) does not accidentally claim a data-loss risk
- [ ] The action list names deferred tickets: constant for `100`, the two doc drifts, the sync-contract spike, the group-registered-watch harness — flagged as *future* tickets per decision #1
- [ ] Read `audit/index.md` as a landing page — all links work, scope statement is clear

## Observations from the phases (recorded, not fixed — read-only ticket)

1. **Line-number drift was widespread** — research/plan line numbers were re-verified at
   implementation time and corrected in the fact base (e.g. `CompletionGlow.duration` :27 not
   :26; `ShowDateState.apply()` :21-24 not :25-28; `NextThingWidget` branch region :62-94 not
   :55-95; `UITestingSeed.persistedKeys` :63-87 not :63-85; `SortOptionStore` lives inside
   `SortOption.swift`, not its own file).
2. **Plan's literal grep/one-liner checks were structurally incapable of passing** for this
   repo: `factbase.tsv` stores file path and line in separate columns, and the cite-check regex
   `[A-Za-z]+\.swift:[0-9]+` truncates `ContentView+Settings.swift` to `Settings.swift`. All
   phases implemented the checks' stated intent (basename+line resolution) instead.
3. **`verify-citations.sh` vs self-test race**: running both concurrently shows a transient
   artifact (self-test temporarily corrupts `factbase.tsv`). Run them serially.
4. **Cluster 1 proof nuance**: the `false,≠nil` completion-transition row is proven unreachable
   as a *settled* render, but the snapshot write precedes the flag write on the same task — the
   proof in `clusters.md` was reworded to the accurate mechanics.
5. `--seed` writes unclamped `completionCount` (T4.5) — intentional but undocumented; flagged for
   a future ticket.

## Workflow

Five phase subagents ran sequentially (one commit per phase), each re-verifying citations
against source, running its automated checks, flipping only automated plan.md checkboxes, and
pushing. Parent ran the full Final Gate suite (12 checks) after Phase 5, fixed one blank-line
factbase citation, and checked off the final-gate items. All manual items remain open for the
user.