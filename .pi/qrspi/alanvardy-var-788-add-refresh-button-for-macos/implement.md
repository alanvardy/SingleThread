# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `7ed3341` | Add `ContentViewModel.refreshManual()` + `isRefreshing` + 5 unit tests |
| 2     | `cf33ea3` | Add macOS refresh button overlay + view-structure test |
| 3     | `389ec0b` | **Removed** macOS UI tests (user decision — host-app conflict with sequential multi-suite runs) |

## Automated Checks

- [x] **Layer 1** (Phase 1): `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/ContentViewModelTests` — 10/10 green (5 existing + 5 new `refreshManual*` tests; the 1 s minimum-display hold verified at ~1.03–1.06 s per test)
- [x] **Layer 2** (Phase 2): `make lint` — 0 violations in 165 files (SwiftFormat + SwiftLint `--strict`); no `type_body_length` breach — inline overlay kept, `ContentView+macOS.swift` fallback not needed
- [x] **Layer 2** (Phase 2): macOS unit suite `-only-testing:SingleThreadTests` — 377/377 green (incl. `contentViewBodyContainsRefreshButtonOnMacOS` + all Phase 1 tests)
- [x] **Layer 3** (Phase 3): **N/A — removed by user decision**. `SingleThreadUITestsMacOS.swift`, Makefile `mac-ui-test`, `scripts/test.sh` step, and CI `mac-ui-tests` job were **not** added. Full `./scripts/test.sh` gate not re-run after removal (removal restored the pre-Layer-3 pipeline; nothing new added on Layer 3).

## Manual Verification Items (from the plan)

- [ ] N/A (pure logic layer, no UI) — Layer 1
- [ ] N/A (view-structure test is the verification) — Layer 2
- [ ] N/A (Layer 3 removed — no macOS UI tests to run manually)

## Deviations / Notes

- **Layer 3 removed** (user decision, 2026-09-05): macOS UI tests were dropped because they spawn a host-GUI app that conflicts with the repo's frequent sequential multi-suite runs. Documented in `plan.md` Layer 3 with strikethrough touch-points.
- **Plan's Layer 3 code did not work as written** (before the removal decision): `CODE_SIGNING_ALLOWED=NO` crashes the macOS XCTRunner at bootstrap ("signal kill before establishing connection"); `.trait` is not a macOS audit type (compile error); the macOS accessibility audit flags an anonymous ~752×944 pt root element ("Element has no description") with no element-scoped audit API available. Both Phase 1's `clearSkipped` tests and one Layer 2 assertion also required adaptation (see below). None of this shipped.
- **Layer 1 test adaptation**: the plan's literal `clearSkipped` tests did not compile against the current codebase (`InMemoryEventStore.calendars` is `private let`, `allReminders` is `private(set)`, and `skipCurrentReminder()` mutates asynchronously). Seeded `reminders`/`skippedIDs`/`calendars` through the inits instead — deterministic, no async dependency.
- **Layer 2 assertion adaptation**: `String(describing:)` of a SwiftUI view does not expose the accessibility identifier ("refreshButton" appears only in trailing expression text). The macOS assertion was changed to the one structural signature unique to the refresh overlay in the description dump (control-plate `Button` wrapped in `.disabled(...)`), verified to occur exactly once (the gear uses `.contentShape`, no other button uses `.disabled`). Root cause confirmed only by running the full macOS unit suite — a targeted Swift Testing name-match run silently executed zero tests.
- **Follow-up carried from plan**: duplicate-tap during the 1 s hold is dropped silently (same as `WatchReminderViewModel`); a visible acknowledgment of rejected taps would be a follow-up.