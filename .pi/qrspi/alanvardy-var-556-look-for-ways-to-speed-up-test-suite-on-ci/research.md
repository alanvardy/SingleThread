# Research Findings

Repository: SingleThread SwiftUI app (iOS + macOS). Research scope: CI workflow, Xcode build/test configuration, test target composition, caching, lint/format tooling, and local build/test scripts.

## Q1: Trace the CI pipeline end to end — jobs, steps, dependencies, sequencing/parallelization

### Findings
- Exactly one workflow file exists: `.github/workflows/ci.yml` (56 lines). No other files under `.github/workflows/`.
- Workflow name `CI` — `.github/workflows/ci.yml:1`. Triggers are `push` to `main` and `pull_request` to `main` — `ci.yml:3-7`.
- Two jobs: `test` (`ci.yml:10`) and `lint` (`ci.yml:42`). Both run on `macos-26` (`ci.yml:11`, `ci.yml:43`).
- **No `needs:` keys anywhere**, so the two jobs have no dependency and run in parallel on separate runners.
- `test` job steps, in order: `actions/checkout@v4` (`:13`); `maxim-lobanov/setup-xcode@v1` pinning `xcode-version: '26.6'` (`:15-17`); "Override development team" via `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` (`:19-20`); `actions/cache@v4` DerivedData cache (`:22-26`); **Build** (`:28-33`, `timeout-minutes: 20`); **Unit tests** (`:35-40`, `timeout-minutes: 20`).
- `lint` job steps, in order: `actions/checkout@v4` (`:45`); "Install tools" `brew install swiftlint swiftformat` (`:47-48`); **SwiftFormat check** (`:50-52`, `timeout-minutes: 5`); **SwiftLint** (`:54-56`, `timeout-minutes: 5`).
- Sequencing: **parallel across jobs** (test ∥ lint); **sequential within each job** (checkout → setup → env/cache → build → unit-tests; checkout → install → format-check → lint). The "Override development team" step uses a raw `run:` with no `name:` (`:19-20`), unlike the other named steps.

## Q2: How CI invokes `xcodebuild` — arguments, build vs test, simulator destination/runtime, prep

### Findings
- **Build step** (`ci.yml:31-33`): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`. Uses the `build` action (not `build-for-testing`).
- **Unit test step** (`ci.yml:38-40`): `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`. Uses the `test` action.
- Build and test are **separate `xcodebuild` invocations** in two sequential steps; there is no `build-for-testing` / `test-without-building` split, so the `test` action performs its own build phase (the app is compiled in both steps).
- The test step carries **no `-configuration` flag** (falls back to the scheme default); `-only-testing:SingleThreadTests` is the only test filter — no `-skip-testing` appears anywhere.
- Destination is `platform=iOS Simulator,name=iPhone 17` (`ci.yml:32`, `ci.yml:39`) with **no `OS=` key**, so no runtime is pinned — Xcode 26.6 (pinned via `setup-xcode` at `ci.yml:15-17`) selects the available runtime.
- **No simulator preparation**: repo-wide grep finds no `simctl`, `xcrun`, `preboot`, or `bootstatus` in CI; `xcodebuild` boots the simulator on demand. (The only `simctl` mentions are developer notes in `AGENTS.md:6` and an unrelated plan artifact.)
- `DEVELOPMENT_TEAM` is overridden to empty before build/test (`ci.yml:19-20`).

## Q3: Test targets and test cases — unit vs UI, pure vs coupled

### Findings
- Three native targets in the `PBXNativeTarget` section (`project.pbxproj:97-166`): `SingleThread` app (`productType ... application`, `:118`), `SingleThreadTests` (`... bundle.unit-test`, `:141`), `SingleThreadUITests` (`... bundle.ui-testing`, `:164`).
- Both test targets depend on the app target and set `TestTargetID = 51AA3ED5302D5C4500960DFC` (`:181`, `:185`).
- **Unit tests** (`SingleThreadTests/SingleThreadTests.swift`): imports `Foundation` (`:8`), `@testable import SingleThread` (`:9`), `import Testing` (`:10`). One `struct SingleThreadTests` (`:12`) with **7 Swift Testing `@Test` functions** (`:15`, `:25`, `:34`, `:44`, `:54`, `:64`, `:74`). Every test calls `dueStatus(...)` and asserts with `#expect` (or `#require`, `:76-78`). Covers only `dueStatus`; no tests for `ReminderStore`, `ContentView`, or `SingleThreadApp`.
- The function under test is pure: `nonisolated func dueStatus` in `SingleThread/ReminderFilter.swift:15` and `enum DueStatus` at `:10`, depending only on `Foundation`.
- Unit tests are **app-hosted**: `BUNDLE_LOADER = "$(TEST_HOST)"` (`project.pbxproj:481`, `:506`) and `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThread.app/…"` (`:499`, `:524`).
- **UI tests** (XCTest, not Swift Testing): `SingleThreadUITests/SingleThreadUITests.swift` (`import XCTest` `:8`; `testExample` `:27` — launches app, no assertions; `testLaunchPerformance` `:38` — `XCTApplicationLaunchMetric`) and `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift` (`runsForEachTargetApplicationUIConfiguration = true` `:14`; `testLaunch` `:23` — screenshot attachment). UI tests use `TEST_TARGET_NAME = SingleThread` (`:548`, `:572`).
- Classification: pure logic (`dueStatus`) vs **app-coupled** unit bundle (`@testable import` + `TEST_HOST`/`BUNDLE_LOADER`) vs **system-framework-coupled** UI tests (`XCUIApplication`, `XCTestCase`, `XCTApplicationLaunchMetric`). EventKit/`ReminderStore` is untested.

## Q4: Build settings and compilation modes in `project.pbxproj`

### Findings
- `objectVersion = 77` (synchronized file groups) — `project.pbxproj:6`; `BuildIndependentTargetsInParallel = 1` — `:172`.
- `DEBUG_INFORMATION_FORMAT`: Debug `dwarf` (`:306`), Release `dwarf-with-dsym` (`:368`).
- `SWIFT_OPTIMIZATION_LEVEL`: Debug `-Onone` (`:330`); Release unset (Xcode default `-O`).
- `GCC_OPTIMIZATION_LEVEL`: Debug `0` (`:314`); Release unset (default).
- `ONLY_ACTIVE_ARCH`: Debug `YES` (`:328`); Release unset.
- `ENABLE_TESTABILITY`: Debug `YES` (`:309`); Release unset.
- `SWIFT_COMPILATION_MODE`: Release `wholemodule` (`:384`); Debug unset (default `incremental`).
- `SWIFT_VERSION = 6.0` set **per target** (not at project level): app `:428`/`:473`, tests `:497`/`:522`, UI tests `:546`/`:570`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` set **on the app target only** (`:425`, `:470`); absent on both test targets (so test code defaults to `nonisolated`).
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` on all three targets, both configs (`:424`/`:469`, `:494`/`:519`, `:543`/`:567`).
- Distribution pattern: **compilation/debug-info settings live only in the two project-level configs** and are inherited by all targets; **Swift language/concurrency settings are repeated per target**.

## Q5: Build output caching in CI

### Findings
- The only cache is `actions/cache@v4` in the `test` job (`ci.yml:22-26`); the `lint` job has no caching.
- Cached path (`ci.yml:24`): `~/Library/Developer/Xcode/DerivedData/SingleThread-*` (glob matches Xcode's per-project `SingleThread-<hash>` subfolder).
- Cache key (`ci.yml:25`): `derived-data-${{ runner.os }}-xcode26.6-${{ hashFiles('SingleThread/**/*.swift') }}` — literal prefix + `runner.os` + hardcoded `xcode26.6` + hash of `SingleThread/**/*.swift`.
- Restore key (`ci.yml:26`): `derived-data-${{ runner.os }}-xcode26.6-` (single prefix, no hash).
- `hashFiles` covers **only** `SingleThread/**/*.swift` — excludes `SingleThreadTests/**`, `SingleThreadUITests/**`, `project.pbxproj`, entitlements, and asset catalogs; the Xcode version is hardcoded rather than derived from `setup-xcode`.
- Cache **miss**: different `runner.os`, changed `xcode26.6` string, first run/eviction, or a hash change with no prior prefix match. **Partial restore**: a `SingleThread/*.swift` change alters the hash → exact-key miss → falls back to the most recent prefix match (possibly stale). Changes to test sources, `project.pbxproj`, entitlements, or build settings do **not** invalidate the key.
- Local `.gitignore:4` ignores `DerivedData/` (unrelated to the CI path, but documents DerivedData is uncommitted).

## Q6: SwiftLint and SwiftFormat provisioning and configuration

### Findings
- Provisioned in CI via `brew install swiftlint swiftformat` (`ci.yml:48`) — no version pin, no `mint`, no tool cache.
- Invocations: SwiftFormat check `swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/` (`ci.yml:52`); SwiftLint `swiftlint lint --strict --config .swiftlint.yml` (`ci.yml:56`). `--strict` promotes warnings to errors; `--lint` is check-only.
- `.swiftlint.yml`: `included` paths `SingleThread`, `SingleThreadTests`, `SingleThreadUITests` (`:2-5`); `disabled_rules` (`:8-14`): `single_test_class`, `balanced_xctest_lifecycle`, `empty_xctest_method`, `final_test_case`, `multiple_closures_with_trailing_closure`, `type_name`; thresholds `line_length` 120/150 (`:17-19`), `cyclomatic_complexity` 12/15 (`:21-23`), `type_body_length` 500/600 (`:25-27`), `file_length` 650/800 (`:29-31`); `force_cast`/`force_try` severity `warning` (`:34-37`); `opt_in_rules` (12 rules) (`:40-53`); `identifier_name.excluded` = `id, e, d, rt, to, gvm` (`:56-62`).
- `.swiftformat`: `--swiftversion 6.0` (`:2`); `--indent 4`, `--wraparguments before-first`, `--wrapcollections before-first`, `--closingparen same-line` (`:5-8`); `--enable blankLinesAroundMark, organizeDeclarations, preferSwiftTesting` (`:11-13`); `--disable andOperator, isEmpty, trailingClosures, trailingCommas, wrapMultilineStatementBraces` (`:14-18`); `--exclude SingleThreadUITests` (`:19`).

## Q7: Makefile and `scripts/test.sh` vs CI

### Findings
- `Makefile`: `SIM := platform=iOS Simulator,name=iPhone 17` (`:1`); `.PHONY: build test clean lint format` (`:3`); `build` (`:5-6`) `xcodebuild … -configuration Debug build`; `test` (`:8-9`) `xcodebuild test … -only-testing:SingleThreadTests`; `clean` (`:11-12`) `xcodebuild … clean`; `lint` (`:14-16`) swiftformat `--lint` + swiftlint `--strict`; `format` (`:18-20`) swiftformat + `swiftlint --fix`.
- `scripts/test.sh`: `set -euo pipefail` (`:2`); `SIM`/`SCHEME` (`:5-6`); `cd` to repo root (`:8`); **format/fix** — `swiftformat …` + `swiftlint --fix --config .swiftlint.yml` (`:11-12`); SwiftFormat check `--lint` (`:16`); SwiftLint `--strict` (`:20`); build (`:24-26`); unit tests (`:30-32`); prints `✅ All CI checks passed.` (`:35`).
- **Byte-identical shared commands**: `xcodebuild … -configuration Debug build` (Makefile:6, test.sh:24-26, ci.yml:31-33); `xcodebuild test … -only-testing:SingleThreadTests` (Makefile:9, test.sh:30-32, ci.yml:38-40); `swiftformat --lint …` (Makefile:15, test.sh:16, ci.yml:52); `swiftlint lint --strict --config .swiftlint.yml` (Makefile:16, test.sh:20, ci.yml:56). Destination string and `-only-testing:SingleThreadTests` are identical everywhere.
- **Differences**: format/`--fix` is local-only (test.sh:11-12, Makefile:18-20; absent in CI); CI provisions tools via brew (`ci.yml:48`) while local assumes installed; CI pins Xcode 26.6 (`ci.yml:15-17`); CI overrides `DEVELOPMENT_TEAM` (`ci.yml:19-20`); CI caches DerivedData (`ci.yml:22-26`); CI splits into two parallel jobs vs `test.sh`'s single sequential script (format → check → lint → build → test, `:10-32`); `make clean` has no CI counterpart; CI applies per-step `timeout-minutes` (build/test 20, lint 5).

## Cross-Cutting Observations
- A single destination string `platform=iOS Simulator,name=iPhone 17` is duplicated in `Makefile:1`, `scripts/test.sh:5`, and `ci.yml:32`/`:39`; the `-only-testing:SingleThreadTests` filter is likewise duplicated in all three.
- The **UI test target is never run in CI** — excluded by `-only-testing:SingleThreadTests` in both CI and local tooling.
- CI builds and tests in **Debug only**; there is no Release build/test path in the workflow.
- Build and unit-test are two separate `xcodebuild` invocations (a plain `build` then a `test`), so compilation work is duplicated across the two steps; no `build-for-testing`/`test-without-building` or result-bundling is used.
- `.swiftformat:19` sets `--exclude SingleThreadUITests`, yet every invocation site (`ci.yml:52`, `Makefile:15`/`:19`, `scripts/test.sh:11`/`:16`) still passes `SingleThreadUITests/` explicitly on the command line (observed pattern; also noted in `AGENTS.md`).
- Swift Testing (`@Test`) is used for unit tests; XCTest is used for UI tests; SwiftLint's XCTest-specific rules are disabled accordingly (`.swiftlint.yml:7-14`).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies only to the app target; test targets are `nonisolated` by default (`project.pbxproj:425`, `:470` vs absence in test configs).

## Open Areas
- Release-mode defaults (`SWIFT_OPTIMIZATION_LEVEL`, `GCC_OPTIMIZATION_LEVEL`, `ONLY_ACTIVE_ARCH`, `ENABLE_TESTABILITY`, Debug `SWIFT_COMPILATION_MODE`) are not explicitly set in `project.pbxproj`; values are inferred from Xcode defaults.
- The simulator **runtime** is not pinned (no `OS=` in the destination), so the exact iOS runtime is resolved by Xcode 26.6 at CI runtime and cannot be read from the repo.
- Actual CI timings and DerivedData cache hit-rate are not recorded in the repository, so cache effectiveness cannot be measured from the code alone.
- The macOS app target mentioned in the project description is not surfaced in the workflow (CI only references the iOS `SingleThread` scheme); no macOS destination appears in CI, Makefile, or `scripts/test.sh`.
