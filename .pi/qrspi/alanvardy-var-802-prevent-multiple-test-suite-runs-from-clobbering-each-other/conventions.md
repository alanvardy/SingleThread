# Conventions — shared factual appendix for Structure/Plan

## Canonical commands

### Makefile targets (`Makefile`; SIM overridable `SIM=...` at CLI; `DERIVED_DATA` fixed `DerivedData`, `Makefile:9`)
- `make build` (:18) iOS app `build-for-testing`; `make watch-build` (:21) watch `build`; `make mac-build` (:24) macOS `build` with `CODE_SIGNING_ALLOWED=NO`; `make mac-test` (:27) macOS `test -only-testing:SingleThreadTests`; `make mac-run` (:29-32) build + `open` the app.
- `make test` (:72-74) → `./scripts/test.sh --unit-only`; `make ui-test` (:75-77) → `--ui-only`; `make check` (:95-96) → full `./scripts/test.sh`; `make simverify` (:78-79).
- `make watch-ui-test` (:81-86) / `make watch-test` (:88-93): `test -only-testing:SingleThreadWatchUITests` / `…WatchTests` with `WATCH_TEST_SIM` (default name-only Apple Watch Series 11, `Makefile:7`).
- `make clean` (:98-99) `xcodebuild … clean` (no `-derivedDataPath` — tool default; never called inside runs).
- `make lint` (:101-103) = `swiftformat --lint` over 8 dirs + `swiftlint lint --strict`; `make format` (:105-107) = `swiftformat` + `swiftlint --fix`; `make periphery` (:109-110) = `periphery scan --strict -- -destination "$(SIM)"`.
- `make coverage` (:37-46) / `coverage-ui` (:49-58) / `coverage-all` (:61-70): `rm -rf` own `build/Coverage{,UI,.All}.xcresult`, then `test -enableCodeCoverage YES … -resultBundlePath …`, then `xcrun xccov view --report` (:46, :58, :70).

### scripts/test.sh (`scripts/test.sh`) — the CI-identical gate
- No-arg = full: swiftformat lint + swiftlint + iOS build-for-testing (:211-215) + watch build (:219-223) + Periphery `--skip-build --index-store-path DerivedData/Index.noindex/DataStore` (:227) + iOS unit (:231-237; `-parallel-testing-enabled YES`, allowance 900) + iOS UI (:241-245) + watch build-for-testing with **two** `-only-testing:` flags (:249-256) + local lib_TestingInterop patch (:258-268) + watch UI (:271-275) + watch unit (:279-283) + macOS `test` (:287-292).
- `--unit-only` (:304-315) and `--ui-only` (:325-337): own build-for-testing then `test-without-building`, no parallel flags.
- Env overrides: `SIM`, `WATCH_TEST_SIM`, `RUNTIME_AGE_HOURS` (default 1, :17-18).
- Pre-run: resolve UDID + `simctl boot`/`bootstatus -b` (:44-51) and age-gated XCTestDevices prune (:104).

### scripts/simverify.sh — manual visual gate
- `SIM` default iPhone 17 (:8); pre-boot (:13-18); build-for-testing + `test-without-building` for SingleThreadUITests (:23-35); screenshot `build/simverify-cold-launch.png` (:38-39).

### GitHub Actions (`.github/workflows/ci.yml`)
- 6 jobs on `macos-26`: `unit-tests` (:21-87), `ui-tests-flows` (:89-149), `ui-tests-launch-appearance` (:150-208), `ui-tests-audits` (:209-269), `mac-tests` (:270-321), `lint` (:322-368), `watch-ui-tests` (:369-438). iOS jobs matrix `["iPhone 17", "iPad (A16)"]` (:24-25 etc.); each iOS test step: `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -maximum-test-execution-time-allowance 900` (+ `-retry-tests-on-failure` on UI jobs). UI classes split via `UI_GROUP_A/B/C_ONLY_TESTING` env (:16-18).
- Full gate to run before committing: `./scripts/test.sh` (per AGENTS.md:153-156 the parent/final phase runs it once; phases verify with builds + targeted suites).

## Test-suite inventory

Framework: **Swift Testing** (`import Testing`, `@Test`, `@Suite(.serialized)`) for unit targets; **XCTest** (`XCUIApplication`/`performAccessibilityAudit`) for UI targets. Repo-wide rules: no `-parallelize-testing`/`-jobcount`; `@Suite(.serialized)` on nearly every store/sync suite (shared `EKEventStore` fixtures + real UserDefaults). iOS/macOS run the **same SingleThreadTests bundle** on different destinations.

| Bundle (target/scheme) | Files | Platform gating | Covers |
|---|---|---|---|
| `SingleThreadTests` (iOS + macOS, `SingleThread` scheme) | `SingleThreadTests/*.swift` (75 files): `ReminderStoreTests.swift`, `ReminderStoreGateTests.swift`, `EventKitStoringTests.swift`, `SkipCountStoreTests.swift`, `ExcludedListStoreTests.swift`, `CompletionCounterStoreTests.swift`, `BoolPreferenceStoreTests.swift`, `SortOptionTests.swift`, `PendingCompletionLogicTests.swift`, `UndoStoreTests.swift`, `SkippedReminderSyncServiceTests.swift`, `EnableActionButtonsSyncTests.swift`/`MigrationTests.swift`, `EntitlementStoreTests.swift`/`SyncTests.swift`, `UITestingSeedTests.swift`, `AppGroupTests.swift`, `NotificationPreferenceTests.swift`/`SchedulerTests.swift`, `AppearanceModeTests.swift`, `Settings*Tests.swift`, `Background*Tests.swift`, `ContentViewModelTests.swift`, etc. | `#if os(macOS)` inner blocks e.g. `SingleThreadTests.swift:44,61,84,108,129` (same file runs both destinations); bundle executed with `platform=macOS` destination only in macOS phases | Store persistence (ReminderSkip/SkipCount/ExcludedList/CompletionCounter/PendingCompletion), EventKit round-trips, sync service (Skips/Entitlement/EnableActionButtons/Reschedule), entitlement gating, settings/preferences, appearance, list content, seed parsing, widget/app-delegate surface |
| `SingleThreadUITests` (iOS only, `SingleThread` scheme) | `SingleThreadUITests/*.swift`: `SingleThreadUITests.swift` (incl. `testAccessibilityAudit`, `#if os(iOS)` at :45), `SingleThreadUITestsLaunchTests.swift`, `SingleThreadUITestsAppearanceLaunchTests.swift`, `SingleThreadUITestsFlows.swift`, `ActionButtonsUITests.swift`, `ActionMenuUITests.swift`, `NotificationSchedulingUITests.swift`, `NotificationsSettingsUITests.swift`, `NotificationsUITests.swift`, `SkipNudgeUITests.swift`, `SingleThreadUITestCase.swift` | XCTest, iOS simulator only | Cold-launch screens, appearance variants, flows (skip/complete/undo, persistence-across-relaunch), action buttons/menu, notifications, accessibility audit; seams `--seed` (via `SingleThreadUITestCase.swift:30-32`), `--ui-testing` |
| `SingleThreadWatchTests` (watchOS, `SingleThreadWatch` scheme) | `SingleThreadWatchTests/*.swift`: `ReminderStoreWatchTests.swift`, `ShowCompletionGlowStateTests.swift`, `ShowEnableActionButtonsStateTests.swift`, `WatchAppViewModelTests.swift`, `WatchSyncPipelineTests.swift`, `WatchReminderViewRegressionTests.swift` | Swift Testing; `#if os(watchOS)` in shared files (e.g. `SingleThreadWatchUITests.swift:38`); suite availability fallback means real `.standard` writes on watch | Watch store behavior (pending completions), show-state holders, watch sync pipeline, VM launching, regression |
| `SingleThreadWatchUITests` (watchOS, `SingleThreadWatch` scheme) | `SingleThreadWatchUITests/*.swift`: `SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift` | XCTest, watch simulator | Launch, flows (`--ui-testing` + `--ui-testing-*` family: priority/skip-count/excluded-list/glow/action-menu/gated), `testAccessibilityAudit` |

Unit-test naming: Swift Testing test names must not start with `test`/`testing` (SwiftFormat strips them — AGENTS.md). UI (XCTest) names keep `test…`. Force-unwrapping banned outside tests (relaxed only by `SingleThreadTests/.swiftlint.yml`).

Seam matrix (all in app code; UI tests drive via launch args):
- iOS `--seed '<json>'` → full 24-key reset of AppGroup + standard, then re-seeds (see research.md Q3).
- iOS `--ui-testing` → no reset; `--reset-glow-preference`/`--reset-swipe-preference`/force-enable-action-buttons only.
- watch `--ui-testing[-priority|-skip-count|-excluded-list|-live-excluded|-glow|-glow-disabled|-action-menu|-gated]` → per-launch forced writes.
- `--seed` UI tests must pair with `--ui-testing-noop-settle` + `--ui-testing-reduced-glow` (launch pattern in `SingleThreadUITestCase.swift:30-32`).

## Build/verify gotchas (from research)
1. **Destination pinning**: name-only `iPhone 17`/watch destinations are ambiguous with multiple runtimes → `resolve_sim_udid()` + `,id=` rewrite (`test.sh:22-30, 44-48`); pass `SIM=…,OS=<ver>` or `,id=<UDID>`. Watch override: `WATCH_TEST_SIM='platform=watchOS Simulator,id=…'` (`test.sh:11`).
2. **One xcodebuild test process at a time** (AGENTS.md:19-22). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`. Now enforced on `main` (`b82e54f`: `test.sh` re-execs under `/usr/bin/lockf` on `$HOME/.cache/pi/test-gate.lock`, waits up to `PI_TEST_LOCK_TIMEOUT` (3600s), `PI_TEST_NO_LOCK=1`/CI bypass) — this ticket's Phase 1 was dropped in response.
3. **Watch UI tests locally need a manually paired watch** (`simctl pair <watchUDID> <phoneUDID>`, `.pi/skills/simulator-pairing/SKILL.md:12-15`); CI instead creates a fresh unpaired watch per job (`ci.yml:391-401`).
4. **Do not copy CI's parallel-disable flags locally**: local iOS unit phase runs `-parallel-testing-enabled YES` (`test.sh:234`); the NO/1 flags (`ci.yml:76-77` etc.) are a GitHub virtualized-runner workaround (var-755 plan.md:560).
5. **XCTestDevices runtimes** (~3 GB/UI run, `~/Library/Developer/XCTestDevices`) are pruned only by `test.sh` age-gated (default 1 h, `test.sh:17-18, 104`); CI never prunes (fresh VM). Runner crash dumps: `~/Library/Logs/DiagnosticReports`.
6. **Watch UI runner on this machine** needs `lib_TestingInterop.dylib` embedded into `SingleThreadWatchUITests-Runner.app/Frameworks` (local-only patch `test.sh:258-268`).
7. **All persisted values shared with the watch round-trip through `AppGroup.defaults`, never `UserDefaults.standard`** (AGENTS.md:24-33) — the suite always exists on simulators, so they diverge silently; `AppGroup.swift:16-17` falls back to `.standard` only on watchOS/unregistered sims/previews.
8. **Test hygiene**: inject `defaults: .standard` + UUID keys where possible; any test touching real tiers must `defer { …removeObject }` from **both** tiers when the fallback can bite (see research.md Q3 unit-test hygiene).
9. **`--seed` is the only blanket reset** (`UITestingSeed.swift:62-68`); `--ui-testing` deliberately retains state — persistence UI tests depend on that. A test asserting clean state after `--ui-testing` will fail.
10. **Coverage** is Makefile-only; bundles in `build/` are `rm -rf`'d per target before the run; fixed `-derivedDataPath DerivedData` is shared with all other invocations.
11. **CI cache key is device-agnostic** (`ci.yml:43`) and shared across all 4 iOS jobs/2 devices plus watch source dirs in the hash — DerivedData restored by one leg may contain products from another leg's destination.
12. **macOS suite is the only combined `test` action** (`test.sh:288-292`, `Makefile:27`, `ci.yml:305-313`); everywhere else is `build-for-testing` → `test-without-building`.