# Phase 5 operational notes

## Scope
You produce `audit/findings.md` (severity-ranked T1–T4 findings + prioritized action list) AND
`audit/index.md` (the assembled report landing page).

## Deliverable requirements (beyond the section text above)
1. Re-verify every `file:line` citation against source; adjust when drifted. Keep the
   severity-tier semantics: T1 = reachable contradiction/data loss; T2 = cross-target
   divergence; T3 = dual-read-path drift; T4 = hygiene/naming/doc drift. Ensure T4.4 (6 ×
   Show*Preference) does NOT claim a data-loss risk.
2. **Every finding's Evidence must cite ≥1 factbase.tsv entry** — for each cited file:line,
   confirm a row exists (add rows where missing, byte-exact lineText, well-formed TSV).
3. Cluster-to-finding mapping (Automated check): completion-transition → T1.1, branch-ordering →
   T2.2, entitlement gate → T4.1, dictation → T1.1. If the finding numbering shifts, keep the
   mapping explicit.
4. Action list items are future/deferred tickets — NOT in-scope for this ticket. Ensure the
   list names: the `100` constant, the two doc drifts (AppGroup.swift, AppViewModel.swift:211),
   the `--seed` unclamped-count documentation, the sync-contract spike, the group-registered
   watch harness spike.
5. **index.md**: assembles the report — it must link ALL five artifacts (factbase.tsv,
   inventory.md, clusters.md, enums.md, findings.md) with relative links, restate the
   verification commands (verify-citations.sh + self-test), and state the read-only scope
   clearly.

## Verification (run these; they are the plan's Automated checks)
- Ordering invariant: no T2 finding before a T1; no T3 before a T2; no T4 before a T3 — grep
  tier labels and verify monotonic ordering across findings.md.
- Every finding cites ≥1 factbase.tsv entry (grep each Evidence file:line).
- Every Stage-3 cluster has ≥1 finding (the mapping above).
- Action list items flagged deferred/separate-ticket, not in-scope.
- `bash <audit>/verify-citations.sh` still exits 0.
- index.md links all five artifacts; all five files exist.
- `audit/factbase.tsv` well-formed after any additions.

## plan.md checkboxes
Flip to `- [x]` ONLY the Phase 5 "#### Automated" items you actually ran and passed (both the
findings.md section's and the index.md section's). Leave all "#### Manual" items unchecked.

## Commit + report
- `git add` ONLY `audit/findings.md`, `audit/index.md`, factbase.tsv extensions (if any), and
  your plan.md checkbox edits. Commit message:
  `Phase 5: Severity ranking + prioritized action list`. Push the branch.
- After committing, confirm `git log --oneline -2` shows your commit as HEAD and `git status
  --short` shows nothing intended left behind.
- End your reply with exactly one line:
  `PHASE_RESULT phase=5 sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>`.
If the plan's expectations do not match the codebase in a way you cannot resolve, set
status=issue (or blocked) and explain concisely at the TOP of your reply.