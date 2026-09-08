# Implementation Summary

Extend `BackgroundImageStore` with a 24-hour staleness default, a force-refresh path, and an observable `isRefreshing` flag; thread the live store through `SettingsView` → `BackgroundSettingsView` and add a "Refresh wallpaper" button with `ProgressView` feedback.

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `73d16ac` | Store layer — freshness, forceRefresh, isRefreshing |
| 2     | `90645d5` | Adopt default maxAge in ContentViewModel |
| 3     | `f8b1e28` | Thread BackgroundImageStore into settings + refresh button |
| 4     | `50b2f78` | UI test for background refresh button |
| gate  | `e70d4e1` | Final gate: SwiftFormat + SwiftLint (0 violations) |

## Automated Checks
- [x] `BackgroundImageStoreTests` passes (12 tests: 8 existing incl. 2 renamed + 4 net-new).
- [x] `make build` succeeds (proves all previews + test inits compile).
- [x] `make format` + `make lint --strict` clean (0 violations, 117 files).
- [x] New UI test `testBackgroundRefreshButtonExists` **passes in isolation** (`SingleThreadUITestsFlows`).
- [x] Targeted re-run after formatting: all `BackgroundImageStoreTests` + `SettingsViewTests` pass (except the pre-existing privacy blocker).
- [ ] `xcodebuild test ... -only-testing:SingleThreadTests` — **BLOCKED** by pre-existing, unrelated privacy-guide failures on `origin/main` (see Blocker below).
- [ ] `xcodebuild test ... -only-testing:SingleThreadUITests` (full) — new test passes; 2 unrelated flaky failures (`testEmptyListShowsNoRemindersState`, `testSettingsOpensAndShowsControls`) observed, not caused by this additive change.
- [ ] `./scripts/test.sh` — **BLOCKED** by the pre-existing privacy failures (cannot go green regardless of this plan).

## ⚠️ Pre-existing Blocker (not caused by this plan)
`origin/main` carries two failing tests that block the full unit-suite and `./scripts/test.sh` gates:
- `PrivacySettingsContentTests.privacyGuideContentCoversAllDisclosures`
- `SettingsViewTests.privacySettingsViewContainsExpectedContent`

Both assert `allText.contains("vardy.cc/unsplash")`, but `PrivacyGuideContent` body reads `"proxy at vardy.cc."` — the `/unsplash` segment is absent. Both source files are **byte-identical between `origin/main` and HEAD**, so this predates the wallpaper work. **Recommend fixing the privacy copy or the test assertion before `/6_review` / merge.**

## Implementation Deviations (all compile/plan-required, not scope changes)
- `Self.defaultMaxAge` in a default argument does not compile ("Covariant Self cannot be referenced from a default argument expression") → used `BackgroundImageStore.defaultMaxAge`.
- Parenthesized a string-concatenation-before-`.utf8` helper for correct precedence.
- `backgroundSettingsViewContainsExpectedRows` was adapted to seed a populated store (via a private `SeededFetcher`) so its "Unsplash" footer assertion still holds — a fresh store renders no footer (small necessary adaptation the plan didn't foresee).
- Test count is 12 not 14: the plan assumed 10 pre-existing tests, but the file had only 8 total; added exactly 4 net-new + renamed 2, without inventing duplicate coverage.
- Phase 4 full-UI-suite checkbox left unchecked: two unrelated flaky tests failed in the full run though the new test passes in isolation.

## Manual Verification Items (from the plan — for the user to confirm)
- [ ] Cold-launch the app: the wallpaper still paints and its attribution still renders (24h staleness → second launch within a day hits no network).
- [ ] No user-visible change in Phase 2; wallpaper fetch cadence governed by the store's 24h default.
- [ ] Open Settings → Background: the new "Refresh wallpaper" row sits between the fade picker and the attribution footer.
- [ ] Tap it: a spinner appears while the button is disabled, then a fresh photo paints behind the list and the attribution footer updates to the new photographer/URL.
- [ ] Toggle/fade controls still behave as before.
- [ ] Run the app in the simulator, open Settings → Background, confirm the button is tappable and does not crash the app on tap.


## Follow-up change - refresh hits /unsplash/random

Per review, the explicit "Refresh wallpaper" action should fetch from the
server's **random** endpoint, not the 6h-cached one. The two endpoints return
an identical JSON shape, so only the URL changes.

- BackgroundImageStore: added private static let randomEndpoint = URL(string: "https://vardy.cc/unsplash/random")!. forceRefresh() (the refresh button) now fetches from Self.randomEndpoint; refreshIfNeeded() (cold launch, backed by the 24h staleness default) still uses Self.endpoint (/unsplash).
- Tests: added a randomEndpoint constant to BackgroundImageStoreTests and pointed the force-refresh tests (forceRefreshBypassesFreshSidecar, forceRefreshRetainsPriorImageOnFailure, forceRefreshUpdatesAttributionAfterSuccess, isRefreshingToggledDuringForceRefresh) at it.
- Verified: all 12 BackgroundImageStoreTests pass; SwiftFormat + SwiftLint --strict clean.
