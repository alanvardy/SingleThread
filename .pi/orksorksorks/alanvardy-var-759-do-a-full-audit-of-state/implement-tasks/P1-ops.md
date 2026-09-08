# Phase 1 operational notes

## Scope
You produce the FACT BASE, the bottom layer everything else cites:
`audit/factbase.tsv`, `audit/verify-citations.sh`, `audit/verify-citations-self-test.sh`.

## Deliverable requirements (beyond the section text above)
1. **Directory**: ensure `audit/` exists under `.pi/qrspi/alanvardy-var-759-do-a-full-audit-of-state/`.

2. **factbase.tsv** — header `id\ttarget\tnode\tfile\tline\tlineText`, then one row per
   state-value declaration/read/write. Compile from research.md Q1–Q7, **re-verifying every
   line number and line text against the actual source**. Coverage:
   - All **23 production persisted keys**: `appearanceMode`, `textSize`, `allowsLandscape`,
     `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned`,
     `enableActionButtons`, `showSwipePrompt`, `showUndoButton`, `notificationsEnabled`,
     `notificationIntervalHours`, `showUndatedReminders`, `sortOption`, `showDate`, `showList`,
     `showRecurrence`, `showAlarms`, `showCompletionGlow`, `skippedReminderIdentifiers`,
     `excludedListTitles`, `completionCount`, `pendingCompletionIdentifiers`. Each key needs
     ≥1 row per node: declaration, read, write (the "triplet invariant"). Declaration rows
     include the `@AppStorage` lines and store-property lines; read/write rows come from the
     Q1 read/write site tables, Q5 sync receive, Q6 writer inventory, and bypass writes.
   - **In-memory store properties** for the store-mirror table Phase 2 needs
     (`ReminderStore.reminders/hasHidden/availableLists/authorizationStatus/skipGeneration/
     loadsReminders/entitlementStore/undoStore/visibleReminders/allSkipped/canMutate/
     hasResolvedEntitlement/sortOption/showsUndatedReminders/skippedIDs/excludedListTitles/
     completionCounter/pendingCompletions`, `EntitlementStore.isEntitled/hasResolvedEntitlement`,
     `EntitlementState.isEnabled`, `WatchReminderViewModel` properties,
     `CompletionGlow.isActive/duration`, `DictationViewModel` properties,
     `ReminderDictation.isRecording`, `UndoStore.lastCompletedReminder/hasUndoableReminder`,
     `BackgroundImageStore` properties, `ResumptionGate.hasResumed`, plus the transient
     cluster-vector rows listed next). Use stable logical `id`s.
   - **Transient rows for the four combinatorial clusters** (Phase 4 and 5 verification greps
     resolve these `id`s): completion-transition (`isShowingCompletionTransition`,
     `transitionReminder`, `CompletionGlow.isActive`), branch-ordering (`reminders`, `hasHidden`,
     `allSkipped`, `authorizationStatus`), entitlement gate (`isEntitled`,
     `hasResolvedEntitlement`, `completionCounter.count`, `canMutate`), dictation
     (`isDictating`, `dictationText`, `dictationError`, `creationFeedback`, `isRecording`).
   - **WatchConnectivity payload keys** from `SkippedReminderSyncService.swift` PayloadKey enum
     (declaration rows) + push/receive/hook rows, with `node=wcPayload` / `node=hook` where
     research.md Q5 indicates.
   - **Test seams**: `UITestingSeed.swift` persistedKeys array (EXACT sub-line numbering —
     re-verify inside the array; the plan warns this may have drifted), `AppViewModel.swift:294`
     seed count write, `WatchAppViewModel.swift:27` gated seam (`node=seam`).
   - **Dual-read sites**: each raw `UserDefaults` read supplementary to `@AppStorage`
     (`node=dualRead`) per research.md Q1.
   - **Bypass writes**: every direct assignment / raw `UserDefaults` write from research.md Q6
     bypass-paths section.
   - `node` ∈ declaration | read | write | dualRead | hook | seam | wcPayload.
   - `target` ∈ ios | watchOS | widget | core.
3. **verify-citations.sh** — implement the CORRECTED (process-substitution) version from the
   section text: accumulates failures via a temp file and reports PASS/FAIL with a count.
4. **verify-citations-self-test.sh** — implement option (b): backup factbase.tsv, corrupt the
   first data row's lineText, run the verifier (expect non-zero), restore, report PASS/FAIL.

## Verification (run these; they are the plan's Automated checks)
- `bash <audit>/verify-citations.sh` exits 0.
- `bash <audit>/verify-citations-self-test.sh` exits 0.
- Triplet invariant grep checks: for each of the 23 keys, count rows with node=declaration ≥ 1,
  node=read ≥ 1, node=write ≥ 1 (use awk one-liners in a `/tmp` script).
- 23-key grep from the section text returns 23.
- Also verify: no bare/empty cells in the TSV (no `\t\t` sequences in data rows).

## plan.md checkboxes
Flip to `- [x]` ONLY the Phase 1 "#### Automated" items you actually ran and passed. Leave all
"#### Manual" items unchecked.

## Commit + report
- `git add` ONLY the audit artifacts (the three files above; the audit dir contents) plus your
  plan.md checkbox edits. Commit message: `Phase 1: Fact base — citation-verified source index`.
  Push the branch to origin.
- After committing, run `git log --oneline -2` (confirm your commit is HEAD) and
  `git status --short` (confirm no intended file was left uncommitted).
- End your reply with exactly one line: `PHASE_RESULT phase=1 sha=<full sha> status=<ok|issue|blocked> note=<one-line summary>`.
If the plan's expectations do not match the codebase in a way you cannot resolve, set
status=issue (or blocked) and explain concisely at the TOP of your reply.