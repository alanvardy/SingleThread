# Conventions — SingleThread

Shared factual appendix for later phases. Dense `file:line` references.

## Canonical commands

Run from the worktree root. `fish` shell — compound commands go in `/tmp/x.sh` via `bash /tmp/x.sh`.

| Purpose | Command | Source |
|---|---|---|
| Build (test-ready) | `make build` → `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug build-for-testing` | `Makefile:35-36` |
| Watch build | `make watch-build` | `Makefile:38-39` |
| Mac build / test | `make mac-build` / `make mac-test` (`-only-testing:SingleThreadTests`) | `Makefile:41-46` |
| Unit tests only | `make test` → `./scripts/test.sh --unit-only` | `Makefile` `test` target |
| UI tests only | `make ui-test` → `./scripts/test.sh --ui-only` | `Makefile` `ui-test` |
| Full CI gate | `make check` → `./scripts/test.sh` (full) | `Makefile` `check`; run via `run-gate` skill only |
| Target one suite/case (bounded) | `scripts/test-one.sh <Target/Suite/case> [seconds]` | `scripts/test-one.sh:10-13` |
| Lint / format | `make lint` / `make format` | `Makefile`; gate uses `swiftlint lint --strict`, `swiftformat --lint` (`scripts/test.sh:228-233`) |
| Periphery | `make periphery` → `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` | `scripts/test.sh:278-279` |
| App-Group notify probe | `bash scripts/check-appgroup-notify.sh` | `.pi/skills/ai-sorting/SKILL.md` |

Full gate pipeline order (`scripts/test.sh`): wrapper check `:132`, deployment-target/floor check `:149`, format+lint `:223-233`, warning-check self-test `:236`, build `:240`, watch build `:270`, periphery `:278`, UI tests `:282`, watch UI tests `:290`, watch unit tests `:320`, macOS unit tests `:328`; `--unit-only` runs macOS-native `SingleThreadTests` (`:343-349`), `--ui-only` builds+UI test (`:357-371`).

## Destination & simulator conventions

- Precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default `iPhone 17` (`Makefile:1-4`; `scripts/test.sh:47-72`). `.simulator_id` for this worktree = `5B8A7B5E-A420-4DC0-87EF-AE12FE148B4B`.
- `resolve_sim_udid` matches the device name anchored at line start to avoid the leftover `Gate iPhone 17` sim (`scripts/test.sh:33-41`); name-only destinations are pinned to a UDID and pre-booted (`:28-72`).
- Watch UI tests need a concrete watch UDID: `WATCH_TEST_SIM='platform=watchOS Simulator,id=…'`; default `Apple Watch Series 11 (46mm)` (`Makefile:11-17`).
- `scripts/test-one.sh` exits non-zero on a zero-match `-only-testing:` (xcodebuild otherwise prints TEST SUCCEEDED and exits 0) and bounds the run (`scripts/test-one.sh:5,9`).
- One `xcodebuild` test process at a time; on `Busy`/`RequestDenied` shut down sims and kill orphaned `xcodebuild`/`xctest` (see `simulator-pairing` skill).

## Test conventions

- Unit tests: Swift Testing (`import Testing`, `@Test`), no `test`/`testing` name prefix (SwiftFormat strips it). UI tests: XCTest, keep `test…` names, SwiftFormat-excluded (`SingleThreadUITests`). Watch UI tests are XCTest and NOT excluded.
- Swift Testing single-case form must be suite-level or `case()` — a bare `<Target/Suite/case>` matches zero.
- App target enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `SingleThreadCore` does not, so its types annotate `@MainActor` explicitly (e.g. `AIReminderRanking.swift:63-64`).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`; gate fails on any source-located compiler warning; exceptions go to `scripts/xcodebuild-warnings.allow`.
- New test suites must be added to `Makefile` `test` and `scripts/test.sh` when they need explicit `-only-testing` filters.
- Bug fixes must add a unit test reproducing the reported symptom; new feature logic needs happy + sad path coverage.

## Test-suite inventory (relevant subsystems)

| Suite (path under `SingleThreadTests/`) | Covers | Gating |
|---|---|---|
| `SkippedReminderSyncServiceTests.swift` | activation, push/receive round-trips, malformed payloads, hooks, relaunch persistence (also `SkipCountSyncTests`, `AISortOptionTravelTests`) | iOS/watchOS seam |
| `AppViewModelSyncWiringTests.swift:22-27` | injects `FakeSession` into the view model | iOS |
| `RescheduleSyncTests.swift`, `EntitlementSyncTests.swift`, `AppLanguageSyncTests.swift`, `EnableActionButtonsSyncTests.swift` | sync variants | iOS/watchOS |
| `ReminderStoreTests.swift`, `ReminderStoreGateTests.swift` | persistence, writes, skip path, gate | Swift Testing |
| `EventStoreChangedObserverTests.swift`, `StaleReminderRecheckerTests.swift` | `.EKEventStoreChanged` observer + rechecker | Swift Testing |
| `EventKitStoringTests.swift` | `EventKitStoring` seam | Swift Testing |
| `AISortCoordinatorTests.swift:9,187` | debounce/dedupe/generation/reconcile; fakes `CannedRanker`…`FailingRanker`; `@MainActor struct` | Swift Testing |
| `AISortFailureBannerTests.swift`, `AISortRulesStoreTests.swift`, `AISortRulesViewTests.swift`, `FoundationModelsReminderRankerTests.swift`, `SortOptionTests.swift` | AI sorting | Swift Testing |
| `AppGroupTests.swift:26-71` | suite name, `defaultsIsAStableInstance` (`:36-42`), object-filtered observer (`:44-64`), round-trip | Swift Testing |
| `PreferenceHolderTests.swift:16,26` | `PreferenceHolder` vs real `AppGroup.defaults`, defer-restore | Swift Testing |
| `SentryConfigurationTests.swift`, `SentryScrubberTests.swift`, `CrashReportingPreferenceTests.swift`, `SettingsViewTests.swift:42-50` | Sentry config/scrub/consent | Swift Testing |
| UI: `SingleThreadUITests/` (`testAccessibilityAudit()`), `SingleThreadWatchUITests/` | a11y audit + end-to-end flows | XCTest; `--seed '<json>'` scene for write flows |
| Watch unit: `SingleThreadWatchTests/` | watch logic | Swift Testing, run via `-only-testing:SingleThreadWatchTests` |

## Test seams / doubles

- WatchConnectivity: `SkipSyncSession` protocol (`SingleThreadCore/.../SkippedReminderSyncService.swift:18`), `WCSession` conformance (`:36`), `FakeSession` (`SingleThreadTests/TestFixtures.swift:71-104`). Delegate callbacks are invoked directly on the service.
- EventKit: `EventKitStoring` (`EventKitStoring.swift:8`, `EKEventStore` conformance `:43`), `InMemoryEventStore` (`InMemoryEventStore.swift:13`); `ReminderStore.init` injectable with `loadsReminders: false` (`ReminderStore.swift:23`); shared `sharedTestEventStore`/`makeReminder`/`makeCalendar` builders in `TestFixtures.swift`.
- Persistence timing: `ReminderStoreSettle` injectable (`ReminderStore.swift:12,48-50,627`); `StaleReminderRechecker.Sleep` injectable (`StaleReminderRechecker.swift:27,34,46`).
- AI ranker: `AIReminderRanking: Sendable` (`AIReminderRanking.swift:36`); fakes in `AISortCoordinatorTests.swift:9`; tests inject short debounce and `await`.
- Speech: `TestFakeTranscriber: SpeechTranscribing`; background fetch: `FakeBackgroundFetcher`/`GatedBackgroundFetcher`/`SeededFetcher` + `FetchGate` actor rendezvous (`TestFixtures.swift`).
- Deterministic UI write flows: `--seed '<json>'` backed by `InMemoryEventStore`; watch uses `--ui-testing` / `--ui-testing-live-excluded` (`SingleThreadWatch/WatchAppViewModel.swift:312-327`).
- App-Group tests use isolated `UserDefaults.standard` keys with per-test `UUID` suffixes, not the shared suite.

## Build / verify gotchas

- One xcodebuild test process at a time; see `simulator-pairing` skill for `Busy`/`RequestDenied`.
- `make periphery` reads a stale build index after branch switches — clean `DerivedData/` and rerun first (`periphery` skill).
- Xcode 27.0 local and CI agree; split `verify_deployment_target()` before any floor change (`AGENTS.md`).
- Known local-only macOS failures: three `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary) — pre-existing, not debug targets.
- Full gate runs ONCE after phases commit via the `run-gate` skill; phase subagents use build + targeted `-only-testing:` only.
- Never `git stash` to baseline a failure (stashes span branches) — use `git show origin/main:<path>` or a throwaway worktree.
