# Conventions Appendix — build, test, lint and suite inventory

Shared factual reference for Design / Structure / Plan. Dense `file:line` refs;
do not re-open `Makefile` or `scripts/test.sh` to re-derive these.

## Canonical commands

Destination precedence (`Makefile:1-33`, `scripts/test.sh:36-77`): explicit `SIM=`
wins, else this worktree's `.simulator_id`, else `platform=iOS Simulator,name=iPhone 17`.
`scripts/test.sh` pre-boots the resolved sim. `WATCH_TEST_SIM` pins a concrete
watchOS device for watch UI tests (`Makefile:17-27`).

| Goal | Command | Ref |
|---|---|---|
| Full CI-identical gate | `./scripts/test.sh` (or `make check`) | `Makefile:130-131`, `scripts/test.sh:80-97` |
| Unit only | `make test` → `./scripts/test.sh --unit-only` | `Makefile:106-107` |
| UI only | `make ui-test` → `./scripts/test.sh --ui-only` | `Makefile:108-109` |
| Single test | `scripts/test-one.sh <Target/Suite>` | `AGENTS.md`; `scripts/test-one.sh` |
| Build for testing | `make build` | `Makefile:35-36` |
| Watch build / watch UI / watch unit | `make watch-build` / `make watch-ui-test` / `make watch-test` | `Makefile:38-39,111-127` |
| macOS build / unit / run | `make mac-build` / `make mac-test` / `make mac-run` | `Makefile:41-57` |
| Format | `make format` (`swiftformat …` + `swiftlint --fix`) | `Makefile:133-135` |
| Lint | `make lint` (`swiftformat --lint …` + `swiftlint lint --strict`) | `Makefile:127-130` |
| Periphery | `make periphery` → `periphery scan --strict -- -destination "$(SIM)"` | `Makefile:137-139` |

Full pipeline stages (`scripts/test.sh:223-373`): format → SwiftFormat check →
SwiftLint → warning-check self-test → build → watch build → Periphery
(`--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`,
`:278-279`) → UI tests → watch UI tests → watch unit tests → macOS unit tests →
macOS-native unit tests.

Full-pipeline `-only-testing:` filters: `SingleThreadUITests` (`:287`),
`SingleThreadWatchUITests` (`:296`), `SingleThreadWatchTests` (`:297`),
`SingleThreadTests` (`:334`).

Deployment floors enforced by `verify_deployment_target()` (`scripts/test.sh:143-222`):
iOS 17.0 (×8 pbxproj literals), watchOS 11.0 (×6), macOS 26.5 (×6); package
floors `.iOS 17.0` / `.watchOS 11.0` / `.macOS 26.5` (×1 each). Any new target or
literal trips these counts.

Every `xcodebuild` in `scripts/test.sh` must go through `run_xcodebuild`
(`check-warnings.sh`); a bare call fails `verify_xcodebuild_wrapped()`
(`scripts/test.sh:126-141`). Compiler warnings in source are gate failures;
allowlisted toolchain diagnostics live in `scripts/xcodebuild-warnings.allow`.

## Persistence / sync seams (relevant to this ticket)

- `AppGroup.suiteName = "group.app.alanvardy.SingleThread"`; `AppGroup.defaults`
  is a single cached `nonisolated(unsafe) static let` — `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:10,26-27`.
- `SkippedReminderStore` (`ReminderSkip.swift:121-150`, key `"skippedReminderIdentifiers"`) and
  `ExcludedListStore` (`ExcludedListStore.swift:4-30`, key `"excludedListTitles"`) both
  take `defaults:`/`key:` injection; save is whole-array replace.
- `SkipSyncSession` protocol seam — `SkippedReminderSyncService.swift:18-34`;
  fakes `SingleThreadTests/TestFixtures.swift:70-115`,
  `SingleThreadWatchTests/TestFixtures.swift:16-60`.
- App Group contract guard: `SingleThreadTests/AppGroupTests.swift:26-72`.

## Test-suite inventory

Platform gating: `#if os(iOS)||os(watchOS)` marks WatchConnectivity suites;
`#if os(iOS)` marks phone-only wiring suites.

### SingleThreadTests (Swift Testing; serialized where noted)
Sync / persistence:
- `SkippedReminderSyncServiceTests.swift` — main WC service (activation, push
  payload, receive replace/clear/empty/malformed, complete/delete relay +
  unreachable-queue fallback, excluded-list push/receive/no-op); nested
  `SkipCountSyncTests`, `AISortOptionTravelTests`.
- `WatchSyncPipelineTests.swift` (watch target) — watch-side push omits
  phone-only keys, absent-key no-ops, relaunch persistence; nested
  `WatchEnableActionButtonsSyncTests`, `WatchAppLanguageSyncTests` (serialized).
- `EnableActionButtonsSyncTests.swift`, `AppLanguageSyncTests.swift`
  (`@Suite(.serialized)`), `EntitlementSyncTests.swift`, `RescheduleSyncTests.swift`.
- `AppViewModelSyncWiringTests.swift` — real delegate wiring via injected
  `FakeSession` (`#if os(iOS)`).
- `ExcludedListStoreTests.swift` — default-empty, round-trip, replace-not-union,
  `save([])` clears, key isolation.
- `ReminderStoreTests.swift` (`@Suite(.serialized)`, `:19`) — skip store
  behavior, excluded-list set/refresh hooks; nested `ReminderStoreSkipCountTests`,
  `UndoCompletionTests`, `ReloadPendingCompletionTests`, `MakeReminderTests`,
  `ReminderStoreAIRerankHookTests`; inner `#if os(iOS)||os(watchOS)` blocks
  at `:691,827,1150`.
- `ReminderStoreGateTests.swift` (serialized), `EventStoreChangedObserverTests.swift`,
  `SkipCountStoreTests.swift`, `CompletionCounterStoreTests.swift`,
  `PendingCompletionStoreTests.swift`, `ReminderSkipTests.swift`.
- `AppGroupTests.swift` — stable instance + object-filtered observer contract.
- `UITestingSeedTests.swift` — `--seed` JSON parsing, reset clears keys.
- `LaunchArgumentTests.swift` — flag matching/near-miss.

Mac-only known failures (do not debug here): three `EntitlementStoreTests`
(`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
`hostStoreKitIsClean` canary) — pre-existing per `AGENTS.md`.

### SingleThreadWatchTests (Swift Testing)
`WatchSyncPipelineTests.swift`, `WatchAppViewModelTests.swift`,
`WatchReminderViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`,
`WatchSkipButtonAppearanceTests.swift`, `WatchDemoReminderTests.swift`,
`ReminderStoreWatchTests.swift`, and `Show*StateTests.swift`
(`ShowAlarms`/`ShowCompletionGlow`/`ShowDate`/`ShowEnableActionButtons`/`ShowList`/`ShowRecurrence`).

### SingleThreadUITests (XCTest)
`SingleThreadUITests.swift` — includes `testAccessibilityAudit()`
(`performAccessibilityAudit`).

### SingleThreadWatchUITests (XCTest)
`SingleThreadWatchUITests.swift`.

### Test fixtures
- `SingleThreadTests/TestFixtures.swift` — `FakeSession` (`:70-115`,
  `#if os(iOS)||os(watchOS)`), plus transcriber/ranker/notification fakes.
- `SingleThreadWatchTests/TestFixtures.swift` — `WatchFakeSession` (`:16-60`).
- `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift:13` —
  `InMemoryEventStore: EventKitStoring`.
- `SingleThreadTests/.swiftlint.yml` relaxes
  force-unwrap in tests.

### Script test fixtures
`scripts/tests/warning-check/` — warning-checker fixtures, run early in
`scripts/test.sh` (`:236`).

## Build / verify gotchas

- **Destination pinning**: bare `name=iPhone 17` is ambiguous with multiple
  runtimes and can select the leftover `Gate iPhone 17` sim; `resolve_sim_udid`
  anchors the name (`scripts/test.sh:40-50`). Pre-booted by `preboot_sim` (`:52-56`).
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied`, shut
  down sims and kill orphaned `xcodebuild`/`xctest` (`simulator-pairing` skill).
- **Watch UI tests need an unpaired watch pinned by UDID**:
  `WATCH_TEST_SIM='platform=watchOS Simulator,id=<UDID>'` (`AGENTS.md`, `Makefile:17-27`).
- **Swift Testing name matching**: a bare `<Target/Suite/case>` matches zero —
  use suite-level or append `()`; `scripts/test-one.sh` exits non-zero on a
  zero-match and bounds the run (`AGENTS.md`).
- **Unit-test names must not start with `test`/`testing`** — SwiftFormat strips
  the prefix and silently renames (UI-test XCTest names keep `test…`, excluded
  from SwiftFormat).
- **`make periphery` reads a stale build index after branch switches** — clean
  `DerivedData/` and rerun first (`periphery` skill).
- **Gate staging**: phase subagents verify with a build + targeted
  `-only-testing:` suites; the full gate runs ONCE after phases commit via the
  `run-gate` skill (`AGENTS.md`).
- **Shell is fish** — compound commands/heredocs/loops/`VAR=` fail; wrap as
  `bash -c '…'` or write `/tmp/x.sh` (`fish-shell` skill).
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide**; scope overrides in
  the pbxproj, never CLI flags (`AGENTS.md`).
- **Periphery/Xcode**: Xcode 27.0 local and CI (`xcode-27` preview image)
  agree; 27 misses `$`-projection-only `@State` (`periphery` skill).
