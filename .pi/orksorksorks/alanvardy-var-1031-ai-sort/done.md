# Done

- **Branch / head SHA**: `alanvardy-var-1031-ai-sort` @ `1ef2d781` (the
  `done.md` commit that follows is docs-only).
- **Mechanical checks**:
  - `make lint` (SwiftFormat `--lint` + `swiftlint --strict`): 0 violations /
    0 serious.
  - `make build` (iOS simulator): `** TEST BUILD SUCCEEDED **`.
  - `AISortCoordinatorTests`: 14/14 (12 pre-existing + 2 new).
  - `make watch-test`: succeeded (watchOS core compiles and passes).
  - Periphery `--strict` with a clean `DerivedData` and the gate's exact
    invocation: **"No unused code detected."**
  - Full CI-identical gate at `1ef2d781` (dedicated async gate subagent,
    managed worktree; `SIM=platform=iOS Simulator,id=5AEACAB5-…`,
    `WATCH_TEST_SIM=platform=watchOS Simulator,id=3F69EA19-…`):
    deployment-floor check, SwiftFormat apply + check, SwiftLint `--strict`,
    iOS build, watch build, **Periphery clean**, iOS UI tests (incl.
    `performAccessibilityAudit`), watch UI tests, watch unit tests — all PASS.
    macOS unit: 722 passed, **3 failed — the documented pre-existing
    `EntitlementStoreTests` trio** (`isEntitledSurvivesStoreRecreation`,
    `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`), red on
    `origin/main` since `0bcce49f`; CI mac-tests is skipped on non-dependabot
    PRs. No new regressions; the non-zero gate exit is attributable solely to
    that known macOS leg.
  - `make test` (macOS native) locally: same known trio only; the
    `PreferenceHolderTests` flake passed.
- **Review outcome**: no blockers.
  - Two reviewers (core/concurrency + UI/presentation) both returned no
    blockers; both flagged the digest/refresh path, which I verified and
    scoped precisely.
  - Fixes applied (`866af951`):
    1. `AISortCoordinator.digest` now hashes the full `AIReminderCandidate`
       (`Hashable`), so a candidate content change re-ranks even while a
       previous request is in flight (the reviewers' "content-only edits never
       re-rank" was accurate only for the in-flight case; idle edits already
       re-ranked because the dedupe required `pending != nil`).
    2. Dedupe a *completed* identical request when idle, so unrelated
       App-Group writes no longer re-invoke the on-device model for unchanged
       input.
    3. Reset requested/completed digests on the blank/no-ranker path; added a
       `Logger` line on rank failure instead of a silent swallow; identical
       requests still retry after a failure.
    4. `cancel()` the in-flight ranking when leaving `.ai`; registered the
       rule-change observer under `#if os(iOS) || os(macOS)` (the same guard as
       the `onRemindersChanged` hook it duplicates — an initial attempt placed
       it in the iOS-only block and was corrected before commit).
    5. Accessibility label on the AI rules editor.
    6. `NSLock`-isolated the test fakes' counters (removed the nominal
       `@unchecked Sendable` race under the old mutable `callCount`).
  - Red-first proof: against the pre-fix baseline (`HEAD^`), the suite failed
    exactly `reranksWhenContentChangesInFlight` and
    `skipsRepeatedCompletedRequests`; 14/14 green with the fix.
  - Follow-up fix (`1ef2d781`): Periphery `--strict` flagged
    `SwitchableRanker.callCount` as unused after the lock refactor (a computed
    accessor is flagged where the old stored property was not). Fixed by
    asserting it in `retainsPreviousRankingWhenRankerThrows`, which also
    strengthens the test.
  - Optional improvements declined/deferred: `isAIRankingAvailable` remains a
    construction-time snapshot (there is no availability-change notification to
    observe) — deferred as a note only.
- **Remaining manual items**: the on-device checklist from `plan.md`
  (seed + select AI and see the reorder, rule retention across option switches
  and relaunch, unavailable-device footer copy, debounce feel, ranking
  retention on failure, re-rank on skip/excluded-list toggle, watch parity, and
  an Accessibility Inspector / Dynamic Type pass) — still unrun; they require a
  host with Apple Intelligence available. Recorded in `implement.md`.
- **PR**: #211 (draft; 6 checks green).