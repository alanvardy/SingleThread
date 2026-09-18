# Project Conventions — Shared Appendix

Repo root: `/Users/vardy/dev/alanvardy-var-1031-ai-sort` (worktree; git root
`/Users/vardy/dev/SingleThread`). Single view of the build/test/lint facts so
Structure and Plan never re-read `Makefile`, `scripts/test.sh`, or the suite
set.

## 1. Canonical commands

From `Makefile:1-138`:

| Command | What it runs |
|---|---|
| `make build` | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing` (`Makefile:48-50`) |
| `make test` | `./scripts/test.sh --unit-only` (`Makefile:94-95`) — SingleThreadTests on macOS native |
| `make ui-test` | `./scripts/test.sh --ui-only` (`Makefile:97-98`) — iOS UI tests on simulator |
| `make check` | `./scripts/test.sh` (full pipeline: format, lint, build, periphery, unit + UI + watch tests) (`Makefile:115-116`) |
| `make watch-test` | watch unit tests on `$(WATCH_TEST_SIM)` (`Makefile:106-109`) |
| `make watch-ui-test` | watch UI tests on `$(WATCH_TEST_SIM)` (`Makefile:110-114`) |
| `make mac-test` / `mac-build` / `mac-run` | macOS-native build+test (`Makefile:59-70`) |
| `make lint` | `swiftformat --lint` over all 8 source/test dirs, then `swiftlint lint --strict` (`Makefile:100-104`) |
| `make format` | `swiftformat` (same dirs) then `swiftlint --fix` (`Makefile:105-108`) |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` (`Makefile:109-110`) |
| `make coverage` / `coverage-ui` / `coverage-all` | xcodebuild code coverage → `xcrun xccov view` (`Makefile:71-94`) |
| `make reset-storekit` | `bash scripts/reset-storekit.sh` (`Makefile:68-69`) |
| `make simverify` | `./scripts/simverify.sh` (`Makefile:99`) |

Full pipeline inside `scripts/test.sh` (385 lines, `set -euo pipefail`):
`swiftformat` → `swiftlint --fix` → `swiftformat --lint` → `swiftlint lint
--strict` → iOS `build-for-testing` → watch build → `periphery scan --skip-build
--index-store-path DerivedData/Index.noindex/DataStore --strict` → iOS UI tests
(`-only-testing:SingleThreadUITests`) → watch build+UI tests →
watch unit tests → macOS unit tests (`test.sh:259-371`). `--unit-only` /
`--ui-only` branches at `test.sh:373-385`.

Single test: `scripts/test-one.sh <Target/Suite/case> [timeout-seconds]`
(`test-one.sh:1-73`). Exits non-zero when `-only-testing:` matched **zero**
cases (a zero-match run prints `** TEST SUCCEEDED **` and exits 0); default
timeout 600 s bounds runaway foreground suites.

CI: `.github/workflows/ci.yml` — jobs `unit-tests` (iOS sim matrix
`device: ["iPhone 17", "iPad (A16)"]`, `ci.yml:19-22`), `ui-tests-smoke`
(iPhone 17, `ci.yml:84-145`), `mac-tests` (`ci.yml:146-197`), `lint`
(format+lint+watch build+periphery, `ci.yml:199-246`), `watch-ui-tests`
(`ci.yml:247-318`), `secret-scan`. UI tests disable parallel simulator clones:
`-maximum-concurrent-test-simulator-destinations 1` (`ci.yml:63-72,133-142`).

## 2. Destination / simulator pinning

- Precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared
  default `platform=iOS Simulator,name=iPhone 17` (`Makefile:3-7`,
  `test.sh:33-60`). `make` exports `SIM` only when explicitly overridden so
  `test.sh` can resolve `.simulator_id` itself (`Makefile:40-43`).
- `resolve_sim_udid` pins a name-only destination to its concrete UDID; the
  match is **anchored** (`index(s, n " (") == 1`) so a bare `name=iPhone 17`
  cannot select the leftover "Gate iPhone 17" sim (`test.sh:24-32`).
- `preboot_sim` boots the sim so the first test doesn't pay cold boot
  (`test.sh:37-43`; mirrors `ci.yml:43-48`).
- Watch tests use `WATCH_TEST_SIM` — a **concrete**, unpaired watch pinned by
  UDID (`Makefile:13-32`, `test.sh:15-16`); watch **UI** tests specifically
  need an unpaired watch. Name-only watch destinations normalize to
  OS:latest and can match nothing when multiple watch runtimes are installed
  (`test.sh:283-299`).
- macOS unit tests use `platform=macOS` (`Makefile:25`, `test.sh:18`).

## 3. Build/verify gotchas

- **One xcodebuild test process at a time.** On `Busy`/`RequestDenied`, shut
  down sims and kill orphaned `xcodebuild`/`xctest`; remedies in the
  `simulator-pairing` skill.
- **Periphery reads a stale build index after branch switches** — clean
  `DerivedData/` and rerun; local Xcode 27.0 vs CI 26.6 diverges on
  `$`-projection-only `@State` (see the `periphery` skill). CI periphery runs
  `--strict` (`ci.yml:243-245`); the full pipeline uses `--skip-build` with
  the `DerivedData` index store (`test.sh:266-268`).
- **Deployment-target floor guard** (`verify_deployment_target`, `test.sh:147-260`):
  preflight (and full-pipeline) gate that every
  `IPHONEOS/MACOSX/WATCHOS_DEPLOYMENT_TARGET` literal ∈ {17.0, 26.5, 11.0}
  and matches the pbxproj literal counts (8/6/6) and `Package.swift` floor
  literals (1 each). **Any new/changed target or literal flavor must keep
  these counts** — split `verify_deployment_target()` before any floor change.
- **XCTest runtime cleanup**: each UI test run leaves ~3 GB in
  `~/Library/Developer/XCTestDevices`; `test.sh:109-142` prunes entries older
  than `RUNTIME_AGE_HOURS` (default 1), safe under parallel runs.
- **Local-only watch runner fix**: this machine's watchOS sim runtime lacks
  `lib_TestingInterop.dylib`; `test.sh:311-326` copies the Xcode-side lib into
  the runner's Frameworks before watch UI tests (no-op elsewhere; CI is fine).
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf` keeps incremental
  builds fast; release switches to `dwarf-with-dsym`.
- **Pre-existing local macOS failures** (do not debug; CI green on fresh
  runners): `EntitlementStoreTests` — `isEntitledSurvivesStoreRecreation`,
  `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary.
- Test-only launch seams: `--seed '<json>'` (`UITestingSeed.swift`),
  `--ui-testing` (+ `--ui-testing-noop-settle/glow/reduced-glow`,
  `--no-reminders`, `--url-opener-spy`, `--ui-testing-notifications`), watch
  `--ui-testing-priority/skip-count/excluded-list/live-excluded` overrides.
- **Persistence must round-trip through `AppGroup.defaults`**
  (`UserDefaults(suiteName:)`), never `UserDefaults.standard` — on simulator
  the suite always exists so they diverge silently. `SortOptionStore` /
  `BoolPreferenceStore` already default to `AppGroup.defaults`
  (`SortOption.swift:25-28`).

## 4. Test-suite inventory

All unit suites are **Swift Testing** (`import Testing`, `@Test`) unless
noted XCTest. Unit-test names must **not** start with `test`/`testing`
(SwiftFormat strips the prefix and silently renames the function).

### SingleThreadTests/ (unit; macOS native locally, iOS sim + macOS on CI)
Platform gating is file-level `#if os(...)` on line 1, or inline `#if os(...)`
blocks.

| File | Covers |
|---|---|
| `ReminderStoreTests.swift` | visibleReminders filters/ordering `:20-123`, setSortOption reorder + hooks `:184-240`, ordering in skip flows `:368,635,662,688`, verbatim title/notes storage `:1194-1227` |
| `ReminderSkipTests.swift` | `ReminderSortTests` `:134-278` — comparator behavior for all three options, list bucketing, nil-list-last |
| `SortOptionTests.swift` | enum rawValues, allCases, presentation, `SortOptionStore` load/save/fallback `:40-60` |
| `UITestingSeedTests.swift` | `--seed` decode, reset-persisted-state (incl. `"sortOption"` wipe), seeded-store ordering `:186` |
| `SettingsViewTests.swift` | settings-sheet construction `:191-192`, write-back path `:374-400` |
| `ReminderDictationParserTests.swift` | freeform text → title/date/recurrence `:14-327` |
| `TranscriptionAccumulatorTests.swift` | dictation chunk accumulation `:106-109` |
| `ReminderDictationTests.swift` | FakeSpeechTranscriber/DetachedAuthorizationRequiring `:10-93` |
| `SkippedReminderSyncServiceTests.swift` | sync incl. sortOption context `:78,232,247,511` — `#if os(iOS) || os(watchOS)` (`:1`) |
| `EntitlementSyncTests.swift`, `EnableActionButtonsSyncTests.swift`, `RescheduleSyncTests.swift` | sync suites — `#if os(iOS) || os(watchOS)` |
| `AppDelegateTests.swift`, `BackgroundCardTests.swift` | `#if os(iOS)`; `MenuBarExtraPreferenceTests.swift`, `MacOSActionButtonChromeTests.swift` | `#if os(macOS)` |
| ~45 more files | settings, appearance, completion glow, store tests, etc. |

### SingleThreadUITests/ (XCTest; iOS simulator)
- `SingleThreadUITests.swift` — `runsForEachTargetApplicationUIConfiguration = false`; `testLaunchAndRenderSmoke` launches with `["--ui-testing"]`, asserts seeded "Buy groceries" card + action cluster, then `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])` (`.dynamicType`/`.hitRegion` excluded — can hang CI runners). Invoked via `-only-testing:SingleThreadUITests`; smoke also referenced by name in `ci.yml:144`.

### SingleThreadWatchTests/ (Swift Testing; watch simulator)
`ReminderStoreWatchTests.swift`, `ShowCompletionGlowStateTests.swift`,
`ShowEnableActionButtonsStateTests.swift`, `WatchAppViewModelTests.swift`,
`WatchReminderViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`,
`WatchSyncPipelineTests.swift` (sortOption context `:40`), `TestFixtures.swift`.
Run via `-only-testing:SingleThreadWatchTests` on `WATCH_TEST_SIM`.

### SingleThreadWatchUITests/ (XCTest; watch simulator)
`SingleThreadWatchUITests.swift` — smoke test, launches with
`["--ui-testing"]`. XCTest names keep `test…` here (SwiftFormat excludes only
`SingleThreadUITests/`, so watch UI test names must survive format — they are
XCTest, not Swift Testing).

### Widget
**No test target exists.** Widget consumes `ReminderStore` ordering at
`SingleThreadWidget/NextThingWidget.swift:74-82`.

## 5. Tooling config

- `.swiftformat` (21 lines): SwiftFormat 6 features — `organizeDeclarations`,
  `blankLinesAroundMark`, `preferSwiftTesting`; disables `trailingCommas`,
  `trailingClosures`, `isEmpty`.
- `.swiftlint.yml` (92 lines): `included:` at `:2`, excludes at `:86`
  (relaxes rules for test fixtures via `SingleThreadTests/.swiftlint.yml`
  force-unwrap allowance); CI runs `--strict` — every warning is an error.
  Cross-cutting rule: `identifier_name` ≥ 3 chars (exceptions: `id`, `e`,
  `d`, `rt`, `to`, `gvm`). `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  project-wide.
- `.periphery.yml` (15 lines): `retain_swift_ui_previews: true`,
  `report_exclude: ["**/SingleThreadUITests/**"]`.
- Every persisted value shared with the watch must round-trip through
  `AppGroup.defaults` (see §3) — this includes any new key added for
  settings (e.g. sort-related UI state).

## 6. Package/concurrency facts

- `SingleThreadCore/Package.swift`: platforms iOS 17.0 / watchOS 11.0 / macOS
  26.5; single library target processing `Resources`; **no ML/AI SDK
  declared** — Speech/AVFoundation/EventKit/AppIntents are platform SDKs used
  at source level.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on the iOS app and watch
  app targets only. `SingleThreadCore` package, widget, and test targets do
  **not** enable it — annotate `@MainActor` explicitly there. Swift 6
  language mode; `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- New `.swift` files need no pbxproj edit (synchronized groups). A **new test
  target** is not a file-add: pbxproj object IDs, scheme TestAction wiring,
  a `-only-testing:` entry in `scripts/test.sh`, and CI matrix entries.