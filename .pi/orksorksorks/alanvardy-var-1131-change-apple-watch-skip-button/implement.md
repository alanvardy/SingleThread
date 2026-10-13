# Implement: Apple Watch Skip button ellipsis glyph

## Summary

Changed the watch Skip button so that when it opens the three-action menu
(`canShowActionMenu` is true) it renders SF Symbol `ellipsis.circle.fill` and
the accessibility label `SharedStrings.moreAction`, mirroring the iOS
`skipButton` in `ContentView+ActionMenu.swift`. When direct-skipping, it keeps
`circle.slash` / `SharedStrings.skipReminderAccessibility`. `.tint(.orange)`,
`.accessibilityIdentifier("skipButton")` and
`.accessibilityAddTraits(.isButton)` are unchanged.

The icon/label choice is extracted into a pure, watch-target helper so it is
unit-testable without a live store.

## Commit

- SHA: `1046b9dfce1d32e752b5fd0655d96ffea6435ca9`
- Message: `fix(watch): show ellipsis glyph on the action-menu skip button`
- Pushed to `origin/alanvardy-var-1131-change-apple-watch-skip-button`
  (`5d9c4c21..1046b9df`).

## Files changed

1. `SingleThreadWatch/WatchSkipButtonAppearance.swift` (new, lines 1-13):
   `enum WatchSkipButtonAppearance` with `nonisolated static func
   systemImage(opensActionMenu:) -> String` → `"ellipsis.circle.fill"` /
   `"circle.slash"` and `nonisolated static func
   accessibilityLabel(opensActionMenu:) -> LocalizedStringResource` →
   `SharedStrings.moreAction` / `SharedStrings.skipReminderAccessibility`.
   Doc comment notes it mirrors the iOS `skipButton` and that
   `SwipeRevealPanel` is iOS-only (hence the literal symbol).
   `nonisolated` required because the watch target enables
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` while the test target does not.
2. `SingleThreadWatch/WatchReminderView.swift` (lines 148-155): the Skip
   button `Label` now uses `WatchSkipButtonAppearance.systemImage(...)` and the
   `.accessibilityLabel` uses `WatchSkipButtonAppearance.accessibilityLabel(...)`,
   both passing `canShowActionMenu`. `.tint(.orange)`,
   `.accessibilityIdentifier("skipButton")`, `.accessibilityAddTraits(.isButton)`
   untouched.
3. `SingleThreadWatchTests/WatchSkipButtonAppearanceTests.swift` (new, lines
   1-19): Swift Testing `struct` with two non-`test`-prefixed cases covering
   both happy and default paths.

## Verification

- `make format` → passed (228 files corrected, no lint regressions).
- `make lint` → passed, 0 violations / 0 serious (swiftlint --strict).
- `make watch-build` → BUILD SUCCEEDED.
- `make watch-test` → TEST SUCCEEDED. New tests executed (not zero-match):
  - `WatchSkipButtonAppearanceTests/actionMenuOpenShowsEllipsisAndMoreLabel()` passed
  - `WatchSkipButtonAppearanceTests/directSkipShowsSlashAndSkipReminderLabel()` passed
  (Watch tests ran on `Clone 1 of Apple Watch Series 11 (46mm) - SingleThreadWatch`.)
  Note `LocalizedStringResource` does compare with `==`, so no key comparison was needed.

Initial build failed 3 times during iteration: (1) `LocalizedStringResource`
out of scope → added `import Foundation`; (2) MainActor-isolated static funcs
unavailable from the nonisolated test target → marked both funcs `nonisolated`.
Resolved within the 3-attempt bound.

## Staging scope

Committed only the three source/test files. `.pi/orksorksorks/` artifacts and
the pre-existing unstaged `DELETEME` deletion were left untouched (not staged).

## Deviations

- None from the task spec. The `nonisolated` qualifier and `import Foundation`
  were required for the watch target's default-MainActor isolation mode.