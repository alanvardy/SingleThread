# Done

- **Branch / head SHA**: `alanvardy-var-1171-use-toolbars-for-icons` @ `3dfbb0a6`
  (pushed; PR #249 draft). Commits this pass: `f8bd4b30` (review fixes),
  `3dfbb0a6` (Periphery unblock).

## Mechanical checks

- **`make format` / `make lint`** — clean, 0 violations (the branch-caused
  `superfluous_disable_command` at `ContentView.swift:21` was fixed in `f8bd4b30`).
- **Full CI-identical gate** (`./scripts/test.sh`, commit `3dfbb0a6`, dedicated
  async worktree lane):
  - Deployment floors, xcodebuild guards, SwiftFormat, SwiftLint, warning-check
    self-test, iOS build, watch build — ✅ pass.
  - **Periphery — ✅ pass ("No unused code detected")** after the `swipeOffset`
    direct-read fix (`3dfbb0a6`); no new findings.
  - iOS UI tests ✅ 6/6, watch UI tests ✅, watch unit tests ✅.
  - **macOS unit tests — ❌ 1 failure**: `AISortCoordinatorTests/reRanksAfterSilentFallbackClearsTheDigest()`
    (`emitted.count == 3` vs `2`, 25.87 s vs the 25 s `waitUntil` horizon).
    **Pre-existing, unrelated timing flake**: the file is byte-identical to
    `main` (`git diff --stat main -- …/AISortCoordinatorTests.swift` empty), no
    branch commit touches it, and the 25 s horizon was raised on `main`
    (`1de874d5`). The gate lane re-ran the suite in isolation on `platform=macOS`
    and it **passed (25.067 s)** — load-sensitive, not a logic regression.

## Review outcome

- **Reviewer**: no P0/P1 certifiable. iOS-gated host/toolbar, macOS paths
  structurally untouched, gating contract unit-tested, a11y identifiers
  preserved, HIG representation correct.
- **Branch-caused blocker fixed**: dead `// swiftlint:disable:next type_body_length`
  (struct fell under the 500-line budget after the refactor) removed with its stale
  comment.
- **Fixes applied now**: stale `actionCluster` doc reference on `skipButton`
  corrected; empty bottom `ToolbarItemGroup` guarded
  (`!toolbarActionSet.actions.isEmpty`) so free-tier renders no blank bar.
- **Main-origin unblock applied**: `ReminderCardView.swipeOffset` now has a direct
  read (`swipeOffsetBinding`) so Xcode 27 Periphery sees the `@State` used —
  matches the existing `isShowingPurchase` / `localRefreshing` precedent. This is
  an out-of-ticket change needed because `origin/main`'s own CI is currently red
  on the same finding.
- **Optional improvements declined/deferred**: bundling/`AnyView` micro-polish on
  the bottom bar — no concrete finding.
- **Reviewer notes closed by inspection**: undo-item gate parity matches the
  deleted iOS overlay exactly (`hasUndoableReminder && showUndoButton && canMutate`,
  same order).

## Remaining manual items

- Phase 1–4 manual simulator checks from `plan.md`: gear top-right / undo
  top-left only when undoable; free-tier upgrade prompt with no blank bottom bar;
  complete / skip / mic / undo reachable and VoiceOver-labelled; completion-momentum
  overlay (`.padding(.top, 72)`) and AI-sort banner vs the new nav bar; landscape
  rotation; iPad size-class pass.
- **Duo external-screen vertical-toolbar requirement is unverified by design**
  (design decision 9): no external-display `UIScene` and no Duo proxy/hardware run;
  satisfied only by inference ("be a standard component and be resizable" → the
  system relocates the bar). Explicit sign-off needed.
- The macOS unit flake is expected to be green on CI (main's `mac-tests` job passes);
  CI is authoritative.
