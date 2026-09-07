# Implementation Summary

Spike (VAR-766): register the App Group entitlement on the production watch
target, hard-assert the group↔`.standard` divergence in hosted watch unit
tests, and document a reusable harness for successor tickets.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `21129b6` | Entitlements Registration — watch entitlements file + pbxproj wiring (+probe test) |
| 2     | `564fd72` | Harness — Cross-Container Divergence — `AppGroupHarness` + divergence tests |
| 3     | `448a120` | Runbook — `docs/WatchAppGroupHarness.md` |
| —     | `54ae602` | fix: satisfy Periphery strict in watch harness (drop unused import, exercise `suiteExists()`, swiftformat) |
| —     | `<chore>` | chore: QRSPI artifacts + implementation summary |

## Automated Checks

- [x] Phase 1 `make watch-test` — 47 passed / 0 failed (probe `suiteResolvesOnWatch()` green + existing watch suite green)
- [x] Phase 2 `make watch-test` — 44 passed / 0 failed (probe + `completionCountDivergesBetweenContainers` + `writingStandardDoesNotLeakIntoGroup` + existing watch suite)
- [x] SwiftFormat clean on `SingleThreadWatchTests/` (gate formatter: 0 files to reformat)
- [x] SwiftLint `--strict` — 0 violations in 188 files
- [x] Deployment-target / package-floor check — `EXPECTED_TARGET_LITERALS` stays 20
- [x] Periphery `--strict` — "No unused code detected" (after `54ae602`; the plan-mandated `@testable import SingleThreadWatch` and the unused `suiteExists()` were flagged, then fixed)
- [x] iOS unit tests — passed (gate reached the UI stage)
- [ ] iOS UI tests — gate run interrupted by another session's `pkill -9 xcodebuild` on this shared machine; one flake observed (`ActionButtonsUITests.testActionButtonsRenderAndSkipAdvancesCard`) which cannot be a regression from this watch-only diff. **Deferred to CI** (authoritative per AGENTS.md).
- [ ] Watch UI + unit + macOS stages — not reached in the interrupted local gate; covered by CI
- [ ] `./scripts/test.sh` full gate end-to-end — see CI (PR #167) for authoritative result

## Manual Verification Items (from the plan)

- [ ] Phase 1 — probe `suiteResolvesOnWatch()` passed (positive finding — registration takes effect on the watchOS simulator; the "record negative finding and stop" path did not trigger)
- [ ] Phase 2 — `completionCountDivergesBetweenContainers()` passed: no negative finding to record ("no divergence on watchOS simulator" did not occur)
- [ ] Phase 2 — `writingStandardDoesNotLeakIntoGroup()` passed: no negative finding to record (one-way leak did not occur)
- [ ] Phase 3 — read `docs/WatchAppGroupHarness.md`; every command is copy-paste runnable (`make watch-test` verified)
- [ ] Phase 3 — suite referenced as `AppGroup.suiteName`, never a hardcoded literal (verified in runbook + all new test code)
- [ ] Phase 3 — `make watch-ui-test` passes (covered by the full gate's watch-UI stage on `Apple Watch Series 11 (46mm)`; the now-registered watch app launched and passed UI tests)

## Spike Findings

- **Positive**: a group-registered watchOS simulator build resolves
  `UserDefaults(suiteName: AppGroup.suiteName)` (probe green) — App Groups
  work on the watchOS 26.5 simulator when `CODE_SIGN_ENTITLEMENTS` +
  `REGISTER_APP_GROUPS = YES` are set on the watch target.
- **Positive**: group and `.standard` are distinct containers on the watch,
  bidirectionally (both divergence tests green) — the
  receive-into-group / push-from-`.standard` divergence in
  `WatchAppViewModel` is therefore observable on a registered build.

## Observations (not in plan scope)

- Plan's existing-test count ("36 `@Test`s") was stale — 41 pre-existing
  `@Test`s at implementation time; all green.
- Plan's test snippets used `.completionCount` and `+`-concatenated `#expect`
  messages; the former is `.count` in `CompletionCounterStore`, and string
  concatenation does not compile as a Swift Testing `Comment` — both adapted,
  message text preserved.