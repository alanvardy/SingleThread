# Phase 4 operational notes

## Scope
You produce `audit/enums.md` — exactly THREE full enum sketches
(CompletionTransition, EntitlementGate, EmptyState) plus advisory pointers for the remaining
bare-Bool/Int clusters.

## Deliverable requirements (beyond the section text above)
1. Re-verify every `file:line` citation against source; adjust when drifted.
2. Keep exactly three "Enum Sketch N:" sections (N = 1, 2, 3). Note the plan's Sketch 1 has a
   duplicated `case completing(reminder:glowActive:)` line — the intent is a SINGLE case with a
   Bool parameter covering both glow-active and buffer states; sketch it correctly (one case,
   and explain the two sub-states in prose or one case with the parameter).
3. Advisory pointers must enumerate ALL remaining bare-Bool/Int clusters from research Q4:
   the `show*` ×6 Bools, dictation two-machine state, `BackgroundFade` Int namespace, watch
   refresh UI flags — with `file:line` citations, and NO full case-list sketches for them.
4. For automated check "Each sketch's `replaces` fields resolve as real keys in factbase.tsv":
   the field names listed in each sketch's `Replaces` (e.g. `isShowingCompletionTransition`,
   `transitionReminder`, `CompletionGlow.isActive`, `isEntitled`, `hasResolvedEntitlement`,
   `completionCounter.count`, `allSkipped`, `hasHidden`) must exist as `id`s in factbase.tsv.
   Add any missing transient rows (byte-exact lineText) before running the check.
5. Types referenced in sketches (e.g. `EKReminder`, `ReminderDisplay`) must exist in the
   codebase — verify the names; sketch code is advisory pseudo-code, so approximate APIs are
   acceptable, but target names must be real.

## Verification (run these; they are the plan's Automated checks)
- Three enum sketches present: `grep -c "Enum Sketch" audit/enums.md` = 3 (sections).
- Each sketch's `Replaces` field names resolve in factbase.tsv.
- Advisory pointers enumerate `show*` ×6, dictation, `BackgroundFade`, watch refresh flags.
- `bash <audit>/verify-citations.sh` still exits 0.
- `audit/factbase.tsv` well-formed after any additions.

## plan.md checkboxes
Flip to `- [x]` ONLY the Phase 4 "#### Automated" items you actually ran and passed. Leave all
"#### Manual" items unchecked.

## Commit + report
- `git add` ONLY `audit/enums.md`, factbase.tsv extensions (if any), and your plan.md checkbox
  edits. Commit message:
  `Phase 4: Enum assessment — advisory pointers + top-candidate sketches`. Push the branch.
- After committing, confirm `git log --oneline -2` shows your commit as HEAD and `git status
  --short` shows nothing intended left behind.
- End your reply with exactly one line:
  `PHASE_RESULT phase=4 sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>`.
If the plan's expectations do not match the codebase in a way you cannot resolve, set
status=issue (or blocked) and explain concisely at the TOP of your reply.