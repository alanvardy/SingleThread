# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `bdc8ba3` | State contract — EntitlementStore.hasResolvedEntitlement |
| 2     | `2f7aef9` | Testable state injection — unresolved seam + --seed field |
| 3     | `a6e4f3e` | Presentation — gate the iOS bottom-bar freemium cluster |
| fmt   | `76f7b63` | Format: canonical SwiftFormat output for Phase 2 files (gate fix-pass output; CI `lint` SwiftFormat check) |

## Automated Checks
- [x] **Phase 1 — `EntitlementStoreTests`** (5/5) on iPhone 17 sim: `isEntitledIsFalseByDefault`, new `hasResolvedEntitlementIsFalseByDefault`, extended `seamSetsEntitlement` (both flags, both branches), `isEntitledSurvivesStoreRecreation`, `nonMatchingProductIDDoesNotSetEntitlement`.
- [x] **Phase 2 — `EntitlementStoreTests`** (6/6): new `unresolvedSeamLeavesFlagsFalse` + existing.
- [x] **Phase 2 — `UITestingSeedTests`** (14/14): new `parsesEntitlementUnresolved`, `entitlementUnresolvedDefaultsWhenAbsent` + existing.
- [x] **Phase 3 — `SingleThreadUITestsFlows` freemium tests**: new `testUnresolvedEntitlementRendersNoUpgradeButton` green; existing `testUpgradePromptAppearsWhenGated` and `testActionClusterAppearsWhenEntitledAtCap` still pass (unchanged seeds). Verified locally **and** on CI.
- [x] **Phase 3 — `EntitlementSyncTests`** (6/6): `pushAllIncludesEntitledWhenFlagEnabled` still asserts `context["isEntitled"] == false` — watch payload contract preserved.
- [x] **SwiftFormat --lint**: whole tree clean (0/143 files require formatting) after `76f7b63`.
- [x] **SwiftLint --strict**: 0 violations across all changed files.
- [x] **Full CI gate (`ci.yml`, run 33591535887) — ALL 11 JOBS PASS**:
  - `lint` ✓ (SwiftFormat + SwiftLint)
  - `unit-tests (iPhone 17)` ✓, `unit-tests (iPad (A16))` ✓
  - `ui-tests-flows (iPhone 17)` ✓ (incl. `testUnresolvedEntitlementRendersNoUpgradeButton` 8.2 s, `testUpgradePromptAppearsWhenGated`, `testActionClusterAppearsWhenEntitledAtCap`), `ui-tests-flows (iPad (A16))` ✓
  - `ui-tests-audits (iPhone 17)` ✓, `ui-tests-audits (iPad (A16))` ✓
  - `ui-tests-launch-appearance (iPhone 17)` ✓, `(iPad (A16))` ✓
  - `mac-tests` ✓, `watch-ui-tests` ✓
- [x] Local `./scripts/test.sh`: formatted, linted, built, Periphery, unit tests all green. The iOS UI-tests stage hit one pre-existing local-environment failure below; every other stage (watch UI/unit, macOS build+unit) was superseded by the green CI matrix.

## Notes / Observations
- **Pre-existing local failure (NOT a regression, NOT present on CI)**: `testPinWallpaperTogglePersistsAcrossRelaunch` fails on this machine only — `XCTAssertEqual failed: Optional("0") != Optional("1") - Pin wallpaper on should persist across relaunch`, with a `NSMachErrorDomain -308 "(ipc/mig) server died"` trace showing the test's relaunch targeted a different simulator clone (Clone 2, UDID 6DEE2FD8) than its runner. Proven pre-existing: the identical assertion failure reproduces at the pre-change base commit `2e9b562` (before any of these phases), and the test (added in `34a088c`, an earlier ticket) touches none of the freemium/bottom-bar code (uses `--ui-testing`, settings-only). The same suite **passes on CI runners** (ui-tests-flows ✓ on both iPhone 17 and iPad A16). Root cause is this machine's 4-runtime/parallel-clone simulator environment, not the change.
- **Formatting canonicalization**: the gate's SwiftFormat fix pass rewrote Phase 2's `AppViewModel.seededStore` 3-way branch into Swift 6 `if`-expression syntax and normalized a test comment — committed as `76f7b63` so CI `lint` (SwiftFormat check) is green. Semantics identical.
- Phase 3 subagent initially timed out at 30 min retrying the above pin-wallpaper flake; the implementation was already complete and verified (all phase-critical tests passed), so the parent committed it and re-ran `EntitlementSyncTests` + drove the CI matrix to green.

## Manual Verification Items (from the plan)
- [ ] **Phase 1**: Code review — confirm `hasResolvedEntitlement = true` is set at exactly the same sites as `isEntitled` assignment — `refreshEntitlement()` end and `init(testingWithEntitled:)`.
- [ ] **Phase 3**: Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"isEntitled":false}'` — upgrade prompt appears in bottom bar (no regression).
- [ ] **Phase 3**: Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"isEntitled":true}'` — action cluster appears (no regression).
- [ ] **Phase 3**: Visual check (simulator): launch with `--seed '{"reminders":[{"title":"Test"}],"completionCount":100,"entitlementUnresolved":true}'` — bottom bar freemium slot is blank (no upgrade button, no action cluster).