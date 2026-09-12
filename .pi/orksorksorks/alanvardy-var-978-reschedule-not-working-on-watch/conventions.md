# Conventions — Build, Test, Lint, Verify

## Canonical Commands

- `make build` — `xcodebuild -scheme SingleThread -destination '$(SIM)' -config Debug build-for-testing` (Makefile:44-46)
- `make format` — `swiftformat` on 8 source dirs, then `swiftlint --fix` (Makefile:87-89)
- `make lint` — `swiftformat --lint` on 8 dirs, then `swiftlint lint --strict` (Makefile:83-85)
- `make test` — `./scripts/test.sh --unit-only` → `-only-testing:SingleThreadTests` (Makefile:68-70, scripts/test.sh:281-291)
- `make ui-test` — `./scripts/test.sh --ui-only` → iOS sim `test-without-building -only-testing:SingleThreadUITests` (Makefile:71-73, test.sh:294-318)
- `make periphery` — `periphery scan --strict -- -destination "$(SIM)"` (Makefile:90-91); the gate uses `--skip-build --index-store-path DerivedData/... --strict` (test.sh:231-234)
- **CI-identical gate: `./scripts/test.sh`** (also `make check`, Makefile:79) — format→fix, swiftformat lint, swiftlint --strict, iOS build-for-testing, watch build, periphery, iOS UI tests, watch build-for-testing, watch UI tests, watch unit tests, macOS unit tests (test.sh:189-277)
- Other: `watch-build` (Makefile:47-49), `watch-test`/`watch-ui-test` (73-78), `mac-build`/`mac-test`/`mac-run`/`mac-distribute` (51-60), `coverage`/`coverage-ui`/`coverage-all` (62-67), `clean` (81)
- Background gate runs use the `run-gate` skill (async gate subagent in a managed worktree) — never `nohup ./scripts/test.sh &` ad-hoc.

## Destination Pinning

- Precedence: explicit `SIM=` > this worktree's `.simulator_id` UDID > default `platform=iOS Simulator,name=iPhone 17` (Makefile:9-13, scripts/test.sh:8,96-111, scripts/test-one.sh:26-31). Makefile exports `SIM` only when explicitly set (Makefile:15-18).
- `.simulator_id` currently `5A4ADAD5-B040-4EC6-A8B3-8B24ECFBAFFA` (test.sh:24-26). A name-only `iPhone 17` destination is ambiguous when multiple runtimes exist and can match the leftover `Gate iPhone 17` sim — pin with `SIM=`.
- Watch destinations: `WATCH_SIM=generic/platform=watchOS Simulator` for builds; `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` for tests (Makefile:9-13, test.sh:9-11).
- `scripts/test-one.sh <Target/Suite/case> [timeout-seconds]` — runs `xcodebuild test -only-testing:"$ONLY"` with `-resultBundlePath`, default 600 s bound, exits non-zero when zero cases ran (zero-match `-only-testing:` prints `** TEST SUCCEEDED **` and exits 0, silently passing a red-first check) (test-one.sh:1-24,56-68). Case shape: `SingleThreadUITests/SingleThreadUITests/testLaunchAndRenderSmoke` (ci.yml:220).
- One xcodebuild test process at a time; on `Busy`/`RequestDenied` shut down sims and kill orphaned `xcodebuild`/`xctest` (see `simulator-pairing` skill; watch UI tests need a paired watch sim).

## CI Matrix (.github/workflows/ci.yml)

- `unit-tests`: macos-26, matrix `["iPhone 17", "iPad (A16)"]` (2 parallel jobs), `-only-testing:SingleThreadTests`, parallel testing disabled (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`) (ci.yml:12-34,89-104)
- `ui-tests-smoke`: iPhone 17, single smoke case (ci.yml:112-223)
- `mac-tests`: `platform=macOS`, `-only-testing:SingleThreadTests`, `CODE_SIGNING_ALLOWED=NO` (ci.yml:229-278)
- `lint` job: swiftformat --lint + swiftlint --strict + watch build + periphery (ci.yml:286-341)
- `watch-ui-tests`: standalone watch sim "CI Watch S11", watch UI smoke + watch unit (ci.yml:344-443); `secret-scan` with gitleaks (446-472)
- Suite names for `-only-testing:`: `SingleThreadTests`, `SingleThreadUITests`, `SingleThreadWatchTests`, `SingleThreadWatchUITests` (test.sh:250-277)

## Test-Suite Inventory

| Suite | Framework | Coverage | Gating |
|---|---|---|---|
| `SingleThreadTests/` (80 files) | Swift Testing (`import Testing`, `@Test`) | Unit incl. ReminderStoreTests, EventKitStoringTests, RescheduleSyncTests, SkippedReminderSyncServiceTests, UITestingSeedTests | `#if os(...)` inline, e.g. ReminderStoreTests.swift:615 (`os(iOS) \|\| os(watchOS)`), AboutViewTests.swift:26 (`os(macOS)`) |
| `SingleThreadWatchTests/` (8 files) | Swift Testing | Watch unit: ReminderStoreWatchTests, WatchAppViewModelTests, WatchSyncPipelineTests, WatchReminderViewModelTests | runs on watch sim; not in `.swiftlint.yml` `included:` (.swiftlint.yml:3-9) |
| `SingleThreadUITests/` | XCTest (`XCTestCase`, :10) | iOS UI smoke + `testAccessibilityAudit` | SwiftFormat-excluded (`.swiftformat:15-23`); `#if os(iOS)` inline (SingleThreadUITests.swift:58-68) |
| `SingleThreadWatchUITests/` | XCTest (`XCTestCase`, :3) | Watch UI | renamed-keeps-`test…` names (XCTest, not Swift Testing) |

- Test names in Swift Testing suites must **not** start with `test`/`testing` — SwiftFormat strips the prefix and silently renames (Use `isEntitledFallsByDefault` style). UI-test (XCTest) names keep `test…`.
- Force-unwrapping banned outside test code; test fixtures relax via `SingleThreadTests/.swiftlint.yml`.

## Config Files

- `.swiftformat`: `--swiftversion 6.0`, indent 4, `preferSwiftTesting` enabled, `SingleThreadUITests` excluded (.swiftformat:14-23)
- `.swiftlint.yml`: line_length 120/150, cyclomatic 12/15, 41 opt-in rules, `unused_import` analyzer, force_cast/try = warning, identifier_name ≥ 3 chars (exceptions: `id`, `e`, `d`, `rt`, `to`, `gvm`); strict only at invocation (`swiftlint lint --strict`, Makefile:84)
- `.periphery.yml`: project SingleThread.xcodeproj, schemes [SingleThread], `retain_public: false`, retains objc-accessible/annotated + SwiftUI previews, `report_exclude: **/SingleThreadUITests/**`
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide — scope per-target pbxproj overrides; never via CLI flags (conflicts with the SPM package's `-suppress-warnings`)
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch app targets (not core/package/widget/test targets) — async there defaults to `@MainActor`; annotate explicitly in `SingleThreadCore`/tests. `SWIFT_VERSION = 6.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`.

## Gotchas Surfaced by Research

- **AppGroup round-trip rule**: every value shared with the watch must persist via `AppGroup.defaults` (the `UserDefaults(suiteName:)` suite), never `UserDefaults.standard` — on simulator the suite always exists so the two diverge silently. Current reschedule tests use `.standard` + UUID keys (ReminderStoreWatchTests.swift:99, RescheduleSyncTests.swift:17) — not the shared suite.
- `UserDefaults` (incl. `AppGroup.defaults`) is **not `Sendable`** — verify concurrency claims for shared types against the compiler.
- `--seed '<json>'` (InMemoryEventStore) is the deterministic iOS UI-test seam for write flows; `--ui-testing` is the watch seam. On the phone, `--seed` sets `usesInMemoryStore = true` and short-circuits the sync service; `--ui-testing` does not (AppViewModel.swift:142-144,215-231,381).
- `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental builds fast (release uses dwarf-with-dsym).
- `make periphery` reads a stale build index after branch switches — clean `DerivedData/` and rerun.
- Known local-only pre-existing failures (don't debug): three macOS `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) fail on this machine but are green on CI mac runners.