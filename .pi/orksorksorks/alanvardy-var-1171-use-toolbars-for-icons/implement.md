# Implementation Summary

Ticket VAR-1171 — use toolbars for icons. Branch
`alanvardy-var-1171-use-toolbars-for-icons`.

All four phases implemented and committed, one commit per phase (Phase 4's source fix
followed a no-op verification pass). The branch was rebased once onto `origin/main`
before phase work.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| bootstrap | `6a9de7a0` | chore: start alanvardy-var-1171-use-toolbars-for-icons |
| 1 | `399c8fb8` | Phase 1: walking skeleton — real toolbar item on the real root screen |
| 2 | `8af7d134` | Phase 2: all three action items in the bottom group, gated by a tested contract |
| 3 | `6ad6478a` | Phase 3: move top chrome into the toolbar, delete overlays |
| chore | `b1a13f14` | chore: remove DELETEME bootstrap marker |
| 4 | `3c5befca` | Phase 4: gate macOS-only micButton to clear iOS Periphery finding |

## Orchestration notes / deviations

- **Rebase conflict.** `git rebase origin/main` conflicted in `SingleThread/ContentView.swift`:
  Phase 2 had moved the `// MARK: Private` state block; `origin/main` had added
  `@Environment(\.horizontalSizeClass)` / `@Environment(\.verticalSizeClass)` (VAR-1168)
  inside that block. Resolved by deleting the stale (moved-from) copy and re-inserting the
  two environment declarations into the moved-to copy. No other conflict.
- **DELETEME.** The bootstrap marker was sitting deleted-but-unstaged in the worktree;
  committed its removal (`b1a13f14`) before the rebase.
- **Phase 4 expected no source change,** and its first pass committed nothing. The bounded
  checks passed, but `make periphery` surfaced a **new** branch-caused finding:
  `micButton` was unreferenced on the iOS destination after Phase 2 deleted the iOS
  `actionCluster` (its only remaining caller is the macOS `#else`). Per the user's choice
  (Option A), `micButton` was wrapped in `#if os(macOS)` — macOS compiled output is
  byte-identical; committed as `3c5befca`. Periphery then reported only the pre-existing
  `swipeOffset` `$`-projection false positive (identical to `origin/main`).
- **Plan typos adapted (not errors in the code):** the smoke test needs the class-qualified
  form `SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` (bare target form
  matches 0 cases), and `testActionMenuRescheduleFlow` does not exist — the overflow-menu
  intent maps to `testOverThresholdSwipeUpOpensActionMenu`. Both run commands were corrected
  in `plan.md`.
- **Deferred to review:** the full `make check` gate and the iPad `make ui-test` size-class
  run were NOT executed in this step (the full gate belongs to the review step; running the
  iPad UI target here would collide with the review gate). Their `plan.md` boxes are left
  unchecked.

## Automated Checks

- [x] `make build` (iOS) — Phase 1
- [x] `make format` — all phases
- [x] `make lint` — Phase 2, Phase 3
- [x] `make test` incl. new `ToolbarActionSetTests` (5 cases) — Phase 2
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke`
      (includes `performAccessibilityAudit`) — Phase 1, Phase 2, Phase 4 (1 case, PASS)
- [x] `scripts/test-one.sh 'SingleThreadTests/MicrophoneToggleTests/settingsGearButtonIsPresent()'`
      — Phase 1, Phase 3
- [x] `scripts/test-one.sh 'SingleThreadTests/MicrophoneToggleTests/explanatoryLabelAppearsWhenSpeechDeniedAndToggleOn()'`
      — Phase 2
- [x] `make mac-test` — Phase 1, Phase 3, Phase 4 (854 cases, 0 failures)
- [x] `MicrophoneToggleTests` / `ActionButtonTests` (incl. `micButtonHiddenWhenSpeechDenied`)
      — unchanged, green
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLanguageSelectionChangesVisibleString`
      — Phase 3 (taps `settingsButton`)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testUnsupportedStoredLanguageFallsBackToSystem`
      — Phase 3 (taps `settingsButton`)
- [x] Test-assertion accounting: **no retirement needed** — every iOS structural chrome
      assertion is already `#if os(macOS)`-vacuous; the `settingsButton` / `completeButton`
      UI identifiers still resolve to the toolbar items
- [x] `make periphery` — no *new* findings; only the pre-existing `swipeOffset`
      `$`-projection false positive remains (unchanged from `origin/main`)
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testOverThresholdSwipeUpOpensActionMenu`
      (the plan's `testActionMenuRescheduleFlow` equivalent) — Phase 4

### Known non-blocking observations

- `AISortCoordinatorTests/reRanksAfterSilentFallbackClearsTheDigest` is flaky on a loaded
  macOS host (25 s poll-horizon test); it passed in Phase 4's full `make mac-test` and failed
  on one re-run. The branch does not touch `SingleThreadTests/AISortCoordinatorTests.swift`
  (`git log origin/main..HEAD -- <file>` is empty) — pre-existing, not debugged.
- Periphery/Xcode-27 local divergence: `swipeOffset` is a `$`-projection-only `@State`
  false positive, identical on `origin/main`.
- No Duo hardware/proxy run exists (design decision 9) — the one knowingly-unverified claim.

## Manual Verification Items (from the plan)

- [ ] Phase 1 — Record the spike outcome in a short note: chosen shape, whether the photo
      reaches the top edge, whether the card stays vertically centered, whether the bottom
      bar reserves space.
- [ ] Phase 1 — Launch the simulator and tap the toolbar complete — the visible reminder
      still completes and the undo button appears.
- [ ] Phase 1 — Confirm the plate→bar visual weight change is acceptable; if the a11y audit
      reports a local-only `.hitRegion` failure on the smaller bar item, record it (do not
      chase).
- [ ] Phase 2 — Simulator: entitled → complete/mic/skip in the bottom bar; free tier → only
      the upgrade prompt above the bar; speech denied → no toolbar items, "Speech recognition
      is unavailable." + Open Settings still in `bottomBar`.
- [ ] Phase 2 — Note (expected visual change): while dictating, the recording indicator
      shows in `bottomBar` *and* the persistent mic item stays in the bar.
- [ ] Phase 3 — Simulator: gear opens the same Settings sheet; gear shows top-right, undo
      top-left only when an undoable reminder exists.
- [ ] Phase 3 — Check the completion-momentum overlay (`.padding(.top, 72)`) and the AI-sort
      banner against the new nav bar; note any overlap as a follow-up, do not silently
      re-tune paddings.
- [ ] Phase 4 — iPhone and iPad simulator: complete / skip / mic / gear / undo all reachable
      and correctly labeled; VoiceOver reads each item's label.
- [ ] Phase 4 — Rotate (landscape) and re-check bar placement; record the outcome. Duo
      relocation is NOT verified (no Duo hardware/proxy run).
