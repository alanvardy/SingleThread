# Phase 2 operational notes

## Scope
You produce `audit/inventory.md` — the key-centric + store-mirror cross-reference layer.

## Deliverable requirements (beyond the section text above)
1. **Read `audit/factbase.tsv` in full first.** Every `*.swift:<line>` citation you write in
   inventory.md MUST have a matching row in factbase.tsv. If you need to cite a file:line that
   has no row yet, **ADD the row to factbase.tsv** (correct id/target/node/file/line/lineText —
   lineText byte-exact, no tabs in the line). The plan intends Phase 2 to extend the fact base.
2. Use the content structure in the section text exactly: Suite Accessor table, `.standard`
   Keys table (12), App Group Keys table (11), Dual-Read-Path Keys table (the 12 keys listed),
   Single-Path Keys table, Store Mirror Table, Notable Transient State. Fill every placeholder
   (`...`) from factbase.tsv / source re-verification. Add the `Default` column values from
   research.md Q1 where known.
3. Dual-read-path set must be EXACTLY the 12 keys: `enableActionButtons`, `notificationsEnabled`,
   `notificationIntervalHours`, `allowsLandscape`, `appearanceMode`, `showDate`, `showList`,
   `showRecurrence`, `showAlarms`, `showCompletionGlow`, `sortOption`, `showUndatedReminders`.
4. Store mirror table: every store is `@Observable final class` (verify against source, not the
   plan), except explicitly-noted plain classes (`WatchAppViewModel`, `ResumptionGate`) and the
   widget (no view model). Confirm zero `ObservableObject` occurrences across the stores by
   grep of the actual sources. Aim for ~35 rows matching research Q2's enumerated stores.

## Verification (run these; they are the plan's Automated checks)
- Cite-check grep from the section text (every inventory.md `*.swift:<line>` appears in
  factbase.tsv) produces no output. Run it from a script in /tmp if the inline loop fails under
  fish.
- `bash <audit>/verify-citations.sh` exits 0.
- 23-key split: `.standard` rows in the .standard table = 12; App Group rows = 11.
- Store mirror table row count ≈ 35 (count table body rows).

## plan.md checkboxes
Flip to `- [x]` ONLY the Phase 2 "#### Automated" items you actually ran and passed. Leave all
"#### Manual" items unchecked.

## Commit + report
- `git add` ONLY `audit/inventory.md`, the factbase.tsv extension (if any), and your plan.md
  checkbox edits. Commit message:
  `Phase 2: Inventory — key-centric and store-mirror cross-reference`. Push the branch.
- After committing, confirm `git log --oneline -2` shows your commit as HEAD and `git status
  --short` shows nothing intended left behind.
- End your reply with exactly one line:
  `PHASE_RESULT phase=2 sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>`.
If the plan's expectations do not match the codebase in a way you cannot resolve, set
status=issue (or blocked) and explain concisely at the TOP of your reply.