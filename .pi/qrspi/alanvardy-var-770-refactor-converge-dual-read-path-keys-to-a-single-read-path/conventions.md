# Conventions — SingleThread (shared factual appendix)

Companion to `research.md`. Commands, test inventory, and build/verify gotchas so Design/Structure/Plan don't re-open `Makefile`, `scripts/test.sh`, or the `*Tests.swift` set.

## Canonical commands

- **Full CI-identical gate**: `./scripts/test.sh` (no args) — formats, SwiftFormat `--lint`, SwiftLint `--strict`, builds iOS (`build-for-testing`), builds watch, runs Periphery (`--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`), then unit tests (`-parallel-testing-enabled YES`, `-maximum-test-execution-time-allowance 900`), iOS UI tests, watch UI tests (with a local `lib_TestingInterop.dylib` runner fix, see Gotchas), watch unit tests, and macOS unit tests (`scripts/test.sh:1-340`).
- **Faster modes**: `make test` = `./scripts/test.sh --unit-only`; `make ui-test` = `./scripts/test.sh --ui-only` (`Makefile:91-95`).
- **Build**: `make build` (iOS, `build-for-testing`), `make watch-build` (`generic/platform=watchOS Simulator`), `make mac-build` (`platform=macOS`, `CODE_SIGNING_ALLOWED=NO`) (`Makefile:32-40`).
- **Targeted suites** (Swift Testing / XCTest):
  - Unit: `xcodebuild -scheme SingleThread -destination '<SIM>' -only-testing:SingleThreadTests test-without-building` (after `build-for-testing`).
  - iOS UI: `-only-testing:SingleThreadUITests` (XCTest), optionally per-class: `-only-testing:SingleThreadUITests/SingleThreadUITestsFlows`.
  - Watch unit: `make watch-test` (scheme `SingleThreadWatch`, `-only-testing:SingleThreadWatchTests`).
  - Watch UI: `make watch-ui-test` (requires a concrete watch device, `WATCH_TEST_SIM`).
  - macOS unit: `make mac-test`.
- **Lint/format**: `make lint` (SwiftFormat `--lint` over all 8 source/test dirs + `swiftlint lint --strict`); `make format` (SwiftFormat + `swiftlint --fix`). SwiftLint runs `--strict` — every warning fails.
- **Dead code**: `make periphery` (`periphery scan --strict -- -destination "$SIM"`).
- **Coverage**: `make coverage` (unit), `make coverage-ui` (UI), `make coverage-all` (both), via `xccov view --report`.
- **Simulator check**: `make simverify` → `scripts/simverify.sh`.

## Deployment-target guard (part of every `test.sh` run)

- `scripts/test.sh:58-160` hard-fails on drift: all `*_DEPLOYMENT_TARGET` literals in `SingleThread.xcodeproj/project.pbxproj` must be iOS **18.7** (8 targets: app, unit+UI tests, widget…, per comment) and macOS **26.5** / watchOS **26.5** (6 targets); `SingleThreadCore/Package.swift` floors `.iOS = 18.7`, `.watchOS/.macOS = 26.5`. Expects exactly 20 pbxproj literals + 3 package literals (`scripts/test.sh:76-79`). Changing floors requires updating both files and the `EXPECTED_*` counts.

## CI layout (`.github/workflows/ci.yml`)

- **iOS unit + UI build matrix**: `macos-26`, Xcode 26.6, devices `["iPhone 17", "iPad (A16)"]` — unit tests run on both (`ci.yml:20-97`); UI tests are **split into 3 disjoint class groups** via env `UI_GROUP_A/B/C_ONLY_TESTING` (`ci.yml:14-17`): A = `SingleThreadUITestsLaunchTests` + `SingleThreadUITestsAppearanceLaunchTests`, B = `SingleThreadUITestsFlows`, C = `SingleThreadUITests` + `ActionButtonsUITests` — run in 3 parallel jobs × 2 devices (`ci.yml:99-240`).
- **Watch UI job** (`ci.yml:415-500`): creates a fresh standalone watch simulator (`simctl create "CI Watch S11"` with the newest watchOS runtime) because name-only watch destinations are ambiguous on GitHub images; runs `SingleThreadWatchUITests` then `SingleThreadWatchTests`.
- **mac-tests job** (`ci.yml:242-330`): macOS build + `-only-testing:SingleThreadTests` with `CODE_SIGNING_ALLOWED=NO`.
- **lint job** (`ci.yml:332-413`): SwiftFormat lint, SwiftLint strict, watch build, Periphery. Tools installed via mise (`.mise.toml`).
- DerivedData cached per-branch; simulators pre-booted in every job (`ci.yml:48-52`).
- **CI disables parallel simulator clones** (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`) — EventKit teardown SIGTRAPs and device-service lockdown can stall on virtualized runners (`ci.yml:76-84`, `:128-136`).

## Test-suite inventory

### SingleThreadTests/ (61 files, Swift Testing) — runs on iOS sim + macOS, and some files on watch
- `SingleThreadTests` is the only unit target in scheme `SingleThread`; Swift Testing (`import Testing`, `@Test`); test names must NOT start with `test`/`testing` (SwiftFormat `preferSwiftTesting` strips the prefix and renames).
- Platform gating (whole-file unless noted):
  - `#if os(iOS)` (whole file): `AppDelegateTests.swift:1`, `BackgroundCardTests.swift:8`, `ActionButtonTests.swift:8`, `AppearanceModeTests.swift:5`.
  - `#if os(iOS) || os(watchOS)`: `SkippedReminderSyncServiceTests.swift:1`, `EntitlementSyncTests.swift:1` (these run in `SingleThreadWatchTests`'s `-only-testing` too? No — they live in the iOS unit target but gate to iOS+watchOS; watch-unit runs use scheme `SingleThreadWatch`).
  - Section-level `#if os(macOS)`: `AppearanceModeTests.swift:8,31`; `SettingsViewTests.swift:66,73,95,107`; `SettingsViewModelTests.swift:13,18`; `MicrophoneToggleTests.swift:232`; `ReminderStoreTests.swift:557`.
- Preference/store coverage (relevant to the read-path work): `ShowAlarmsPreferenceTests`, `ShowCompletionGlowPreferenceTests`, `ShowDatePreferenceTests`, `ShowListPreferenceTests`, `ShowRecurrencePreferenceTests`, `SortOptionTests`, `ShowDateTests`, `SkipCountStoreTests`, `CompletionCounterStoreTests`, `ExcludedListStoreTests`, `AppGroupTests`, `SettingsViewModelTests`, `UITestingSeedTests`, `SkippedReminderSyncServiceTests`, `EntitlementSyncTests`, `AppearanceModeTests`, `ActionButtonTests`, `BackgroundCardTests`, `ReminderStoreTests`, `ReminderStoreGateTests`, `PendingCompletionStoreTests`, `PendingCompletionLogicTests`, `UndoStoreTests`, `ReminderSkipTests`.

### SingleThreadWatchTests/ (5 files, Swift Testing)
`WatchSyncPipelineTests.swift` (full phone→watch payload round-trips with `.standard` + `"wtest-…"` keys), `ReminderStoreWatchTests.swift`, `WatchReminderViewRegressionTests.swift`, `WatchAppViewModelTests.swift`, `ShowCompletionGlowStateTests.swift`. Run via scheme `SingleThreadWatch`.

### SingleThreadUITests/ (10 files, XCTest)
`SingleThreadUITestsLaunchTests`, `SingleThreadUITestsAppearanceLaunchTests`, `SingleThreadUITestsFlows`, `SingleThreadUITests`, `ActionButtonsUITests`, `SkipNudgeUITests`, `NotificationSchedulingUITests`, `NotificationsUITests`, `NotificationsSettingsUITests`, `SingleThreadUITestCase.swift`, plus launch helpers. XCTest names keep `test…` (SwiftFormat-excluded). Includes `testAccessibilityAudit()` (`performAccessibilityAudit`).

### SingleThreadWatchUITests/ (3 files, XCTest)
`SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift`.

## Load-bearing test seams

- **`--seed '<json>'`** (iOS, driven by `UITestingSeed` + `InMemoryEventStore`) is the deterministic UI-test path for write flows; **`--ui-testing`** for persistence-across-relaunch flows. **Never relaunch with `--seed`** — it calls `resetPersistedState()` wiping both suites (`SingleThreadUITestCase.swift:10-23`; `SingleThreadUITestsFlows.swift:326-328,421-423,526-527,545-546`).
- Seam suite writes: `--ui-testing` → STD only; `--seed` → AG (`completionCount`, `skipCounts`) + STD (`enableActionButtons`); watch `--ui-testing-gated` / `--ui-testing-skip-count` → AG (falls back to STD on watch) (`SingleThread/AppViewModel.swift:284-291,330-373`; `SingleThreadWatch/WatchAppViewModel.swift:26-27,118-121`).

## Gotchas (surfaced by research; see AGENTS.md)

- **Destination pinning**: a bare `name=iPhone 17` destination is ambiguous with multiple runtimes and hangs; `scripts/test.sh` resolves to a concrete UDID (`resolve_sim_udid`, `scripts/test.sh:14-20`) and pre-boots the sim (`:22-25,48-57`). `Makefile`/test.sh accept `SIM=`, `WATCH_TEST_SIM=`. Watch UI tests need a concrete device (`WATCH_TEST_SIM` default `Apple Watch Series 11 (46mm)`) and a *paired* sim for watch UI (`xcrun simctl pair`).
- **One xcodebuild test process at a time** (simulator contention); CI additionally disables clone parallelism (above).
- **Local watch test runner fix**: this machine's watchOS runtime misses `lib_TestingInterop.dylib`; `scripts/test.sh:318-335` copies it into the UI-test runner's Frameworks before watch UI tests (no-op where present; CI unaffected).
- **SwiftFormat renames unit tests** starting with `test`/`testing` — phantom "file reverted" diffs; use declarative names.
- **Force-unwrapping banned outside tests**; test fixtures relax via `SingleThreadTests/.swiftlint.yml`.
- **Shared-suite divergence**: persisted values shared with the watch/widget must round-trip through `AppGroup.defaults`, never `UserDefaults.standard` — on simulator the suite always exists, so the two diverge silently (AGENTS.md). Tests use per-test `UserDefaults(suiteName: "…Tests-\(UUID)")` suites (e.g. `SkipCountStoreTests.swift:69-71`) or UUID keys + `defer removeObject` to stay parallel-safe under Swift Testing.
- **`--ui-testing`/`--seed` seams must also go through the shared suite** where the value is shared (AGENTS.md), e.g. watch `completionCount`/`skipCounts` via `AppGroup.defaults.set`.
- `AppGroup.defaults` = `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` (`SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:11,15-17`); the widget target carries the App Group entitlement (`SingleThread/AppGroup.entitlements:10`), the watch does not (falls back to `.standard`).