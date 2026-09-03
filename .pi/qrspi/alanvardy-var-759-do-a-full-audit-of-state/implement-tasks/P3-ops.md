# Phase 3 operational notes

## Scope
You produce `audit/clusters.md` — four combinatorial cluster matrices + the 11-site
App Group vs `.standard` divergence index.

## Deliverable requirements (beyond the section text above)
1. **Re-verify every `file:line` in the section text against source.** Line numbers in the
   matrices and divergence index (e.g. `WatchReminderViewModel.swift:66-86`,
   `NextThingWidget.swift:55-95`) must match the actual files. Adjust when drifted, but do NOT
   change the substance of the claims (reachable/unreachable/divergence conclusions) — if a
   conclusion is wrong given the code, stop and report (status=issue).
2. **Reachability claims must be load-bearing**: for every `unreachable (proven)` row, actually
   check there is no write path that could produce the vector — trace the code, don't trust the
   plan. Every `reachable` row's path note must resolve to factbase.tsv rows (add rows for any
   cited file:line missing from factbase.tsv — byte-exact, no tabs).
3. **Divergence site citations must resolve in `inventory.md`** (per the Automated check): for
   each of the 11 sites, the cited `file:line` should appear in inventory.md too. If a site's
   citation is absent from inventory.md, extend inventory.md (e.g. in the relevant key row or a
   divergence-notes line) so the citation resolves — while KEEPING the Phase 2 cite-check
   invariant (every inventory.md `*.swift:<line>` exists in factbase.tsv). Prefer extending
   inventory.md minimally over restructuring it.
4. Fill every matrix cell: zero bare `undefined` cells. The four "Open Areas" listed in the
   section text are the only allowed undefined areas — mark them explicitly.

## Verification (run these; they are the plan's Automated checks)
- Every reachable combo's path note resolves in factbase.tsv (grep each cited `file:line` from
  every reachable row).
- Every unreachable(proven) claim verified by tracing write paths (manual code tracing; record
  in your report what you checked).
- All four cluster matrices have zero bare `undefined` cells.
- All 11 divergence sites carry `file:line` citations that resolve in inventory.md.
- `bash <audit>/verify-citations.sh` still exits 0.
- `audit/factbase.tsv` remains well-formed (header intact, no empty cells introduced).

## plan.md checkboxes
Flip to `- [x]` ONLY the Phase 3 "#### Automated" items you actually ran and passed. Leave all
"#### Manual" items unchecked.

## Commit + report
- `git add` ONLY `audit/clusters.md`, factbase.tsv/inventory.md extensions (if any), and your
  plan.md checkbox edits. Commit message:
  `Phase 3: Combinatorial clusters + cross-target divergence analysis`. Push the branch.
- After committing, confirm `git log --oneline -2` shows your commit as HEAD and `git status
  --short` shows nothing intended left behind.
- End your reply with exactly one line:
  `PHASE_RESULT phase=3 sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>`.
If the plan's expectations do not match the codebase in a way you cannot resolve, set
status=issue (or blocked) and explain concisely at the TOP of your reply.