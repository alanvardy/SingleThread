# Done

- **Branch / head SHA**: `alanvardy-var-1165-sentry-error` @ `65a65dbf` (review fix on top of gated `9cba83c5`); pushed to `origin` with `--force-with-lease`.
- **Mechanical checks**:
  - `make format` clean; `make lint --strict` → 0 violations, 233 files.
  - Full CI gate (`./scripts/test.sh`, pinned to the worktree iPhone UDID + watchOS 26.5 UDID) at `9cba83c5`: PASSED deployment-target check, xcodebuild-wrapper check, format, SwiftFormat check, SwiftLint, warning-check self-test, iOS build, and watch build (no un-allowlisted warnings).
  - Gate **FAILED stage-fatal at Periphery** (`SingleThread/ReminderCardView.swift:74:24: Unused property 'swipeOffset'`); the test/UI stages never ran at that commit.
  - Targeted re-verification at `65a65dbf`: `SingleThreadTests/SentryScrubberTests` **15/15**, `SingleThreadTests/BackgroundImageStoreTests` **21/21**, both exit 0 with no zero-match.
- **Review outcome**: one bounded reviewer + parent cross-check — **no blockers**. Applied the two fixes worth doing now: `SentryScrubber.swift` doc now says "the stack contains every image" (code searches the whole frame list, not just the blocked region) and `BackgroundImageStoreTests` renamed `storedImageStillLoadsAndBlocksStaleRefetch` → `storedImageStillLoadsAndBlocksRefetchWhenFresh`. Optional nits **declined**: `appHangStack` multi-exception belt-and-braces (theoretical; events are single-exception) and hoisting the `!isFetching` guard above `loadStoredImage()` (no correctness impact). Accepted residual risk: the coarser BackBoardServices + libxpc image signature can drop a non-backlight system stall traversing both images, bounded by the positional app-frame check (documented in `plan.md`).
- **Periphery failure is main-origin, not this ticket**: `ReminderCardView.swift` is byte-identical to `origin/main` (`ab254d45`), no branch commit touches it, and main's own CI run `39142756669` failed the `lint` job at the same Periphery finding. This is the documented Xcode-27 `$`-projection-only `@State` blind spot. Left unmodified here; it needs its own fix on main.
- **Remaining manual items**:
  - The `plan.md` manual confirmations (captured backlight stack is dropped, app-frame stacks are kept, off-main executor runs off the MainActor, no public surface change) are all covered by the green targeted suites; the operator may spot-check assertions directly.
  - Post-release: confirm Sentry issue 7821993169 stops reporting once a build containing this filter ships.
  - Out of scope: the main-origin `swipeOffset` Periphery red (above), and the plan's deferred EventKit main-thread work.
