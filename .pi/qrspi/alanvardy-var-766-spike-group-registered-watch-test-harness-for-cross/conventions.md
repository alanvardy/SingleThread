# Conventions — shared factual appendix

Repo root: `/Users/vardy/dev/alanvardy-var-766-spike-group-registered-watch-test-harness-for-cross` (branch `alanvardy-var-766-…`). Dense references; verified during research (2026-09-06).

## 1. Canonical commands

| Command | What it runs | Reference |
|---|---|---|
| `make build` / `make test` / `make ui-test` / `make periphery` / `make lint` / `make format` | Standard dev targets; destination via `SIM=` | `Makefile:1-8,20-96` |
| `./scripts/test.sh` | Full CI-identical gate: format, lint, build, Periphery, unit + UI tests (iOS, watch, macOS). **The one full gate; runs once by parent after phases commit.** | `scripts/test.sh` |
| `make watch-ui-test` | `xcodebuild -scheme SingleThreadWatch … test -only-testing:SingleThreadWatchUITests` | `Makefile:87-91` |
| `make watch-test` | `… -only-testing:SingleThreadWatchTests` | `Makefile:92-98` |
| Targeted suites | `xcodebuild -only-testing:SingleThreadTests` / `-only-testing:SingleThreadUITests` / `-only-testing:SingleThreadWatchTests` / `-only-testing:SingleThreadWatchUITests` | `AGENTS.md:26-27` |
| `make format` | `swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/` (UI excluded via `--exclude`); watch dirs included | `Makefile:107,111`; `.swiftformat:21`; `scripts/test.sh:198,203` |
| `swiftlint lint --strict` | Every warning is an error (CI `--strict`) | `AGENTS.md:126-128`; `.swiftlint.yml` |

## 2. Build/verify gotchas (from research)

- **Destination pinning**: two `iPhone 17` instances exist (iOS 26.5 `D7AC0D41-…`, iOS 27.0 `1583C89D-…`) — a bare `name=` hangs. Pin `,OS=` or `,id=` (`scripts/test.sh:22-24`; `AGENTS.md:15-18`). `scripts/test.sh` resolves name→UDID then pre-boots (`:32-48`). `SIM=` env accepted by `scripts/test.sh`/`Makefile`.
- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all` + kill orphan `xcodebuild`/`xctest` (`AGENTS.md:19-21`). **Nothing calls `shutdown all` automatically.**
- **Watch UI tests locally need a paired sim** (`xcrun simctl pair <watchUDID> <phoneUDID>`; runbook `.pi/skills/simulator-pairing/SKILL.md:1-27`). **CI creates a fresh unpaired watch** instead (`ci.yml:391-401`).
- **Local watchOS 26.5 runtime lacks `lib_TestingInterop.dylib`** → `scripts/test.sh:257-269` bundles it into `SingleThreadWatchUITests-Runner.app/Frameworks` (guard `:263-265`); machine-specific, CI no-op (`SKILL.md:22-24`).
- **`EXPECTED_TARGET_LITERALS=20` (8 IPHONEOS + 6 MACOSX + 6 WATCHOS)** guard at `scripts/test.sh:116,176`; **`EXPECTED_PACKAGE_LITERALS=3`** `:117,177` vs `SingleThreadCore/Package.swift:6-8`. Adding/removing a target fails the guard unless constants updated.
- **CI iOS jobs**: `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -maximum-test-execution-time-allowance 900` (`ci.yml:68-77,127-130,143-146,202-205,263-266`) to avoid clone timeouts/SIGTRAP on GitHub runners. Local `scripts/test.sh` parallelizes only the iOS unit phase (`:234`).
- **XCTest runtime pruning**: `scripts/test.sh:16-20,50-84,101-104` prunes `~/Library/Developer/XCTestDevices` older than 1 h (skips symlinks).
- **Concurrency model**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS+watch app targets only; `SingleThreadCore`, widget, test targets need explicit `@MainActor`. Swift 6 + `SWIFT_APPROACHABLE_CONCURRENCY`. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide (only `SingleThreadTests` has the `NO` carve-out for StoreKitTest: `pbxproj:854/883`).
- **SwiftFormat quirks**: unit-test names must not start with `test`/`testing` (renamed silently); UI tests excluded from SwiftFormat; `SingleThreadTests/.swiftlint.yml` relaxes `force_unwrapping`.
- **Checks on simulator use**: `scripts/simverify.sh` (build + `-only-testing:SingleThreadUITests` + screenshot evidence, `:15-39`). `scripts/run-devices.sh` = **real devices via `xcrun devicectl` only** (install/launch, `:12-15,65-98`), unrelated to CI.
- **StoreKit UI tests**: real purchases impossible (`SKTestSession` `disableDialogs = true`, `EntitlementStoreTests.swift:45-48`); premium ID single source of truth `EntitlementStore.unlockProductID`; sandbox tester account needed on device.

## 3. Test-suite inventory

### iOS unit — `SingleThreadTests/` (Swift Testing, `@Test`; `SingleThread.xcscheme` Testables)
Runs: full gate `scripts/test.sh:237`; macOS unit `:292`; unit-only `:307,:315`; CI `ci.yml:62-79,:312`. SwiftLint included (`.swiftlint.yml:7`) with per-dir relaxation; SwiftFormat included; periphery scans scheme `SingleThread` only.

| File | Covers | Notes |
|---|---|---|
| `UITestingSeedTests.swift` | `--seed` parser, defaults, verbatim `completionCount`, reset clears both containers | `@Suite(.serialized)` `:8-9`; shown `:12-151` |
| `SkippedReminderSyncServiceTests.swift` | application-context push/receive, all seven keys, no-op for absent/malformed | `FakeSession` `:15`; isolated via `.standard` UUID keys |
| `EntitlementSyncTests.swift` | completionCount/entitlement travel on push; decode fires hooks | reuses `FakeSession` `:19` |
| `CompletionCounterStoreTests.swift`, `SkipCountStoreTests.swift`, `SortOptionTests.swift`, `BoolPreferenceStoreTests.swift`, `AppearanceModeTests.swift`, `NotificationSchedulerTests.swift` | store round-trips, thresholds, fallbacks | fresh UUID `UserDefaults(suiteName:)` suites (e.g. `BoolPreferenceStoreTests.swift:54-55`) |
| `ReminderStoreTests.swift` | gate (`canMutate` :176-177), skip counts, excluded lists, undo/delete, complete | `CompletedReturningEventStore` `:847`; `.standard` custom keys |
| `EnableActionButtonsMigrationTests.swift` | `.standard`→group one-shot copy; fresh install stays off | constructs `AppViewModel(arguments: [])` `:23,37`; serialized; touches real `.standard`+group |
| `EntitlementStoreTests.swift` | StoreKit session, dialogs disabled | `SKTestSession(configurationFileNamed: "Products")` `:43,63,77` |

### iOS UI — `SingleThreadUITests/` (XCTest)
Runs: `scripts/test.sh:245` (full), `:329,:337` (UI-only); CI split into 3 env groups (`ci.yml:16-18,130,191,250`). Excluded from SwiftFormat (`.swiftformat:21`) and Periphery (`.periphery.yml:16`).

| File | Covers | Notes |
|---|---|---|
| `SingleThreadUITestCase.swift` | base: `launchApp` `:14-19`, `launchSeeded(json:extra:)` = `["--seed", json, "--ui-testing-noop-settle", "--ui-testing-reduced-glow"]+extra` `:21-26`, `assertTogglePersists` (plain `--ui-testing` relaunch) `:50-58` | doc `:10-11`: `--seed` = deterministic write flows; `--ui-testing` = persistence across relaunch |
| `SingleThreadUITestsFlows.swift` | complete/delete/skip/undo/reschedule flows, seeded settings | `launchSeeded` at `:20-347`; seeds with `skipCounts` `:56-64`, `isEntitled`/`entitlementUnresolved` `:344-347` |
| `SingleThreadUITests.swift` | accessibility audit (`testAccessibilityAudit`) | `["--ui-testing","--reset-swipe-preference"]` `:32` |
| `ActionButtonsUITests.swift`, `NotificationsUITests.swift`, `NotificationsSettingsUITests.swift`, `SkipNudgeUITests.swift` | action-bar, notification overlay, notification settings, skip nudge | `--ui-testing` / `launchSeeded` variants |
| `SingleThreadUITestsLaunchTests.swift`, `SingleThreadUITestsAppearanceLaunchTests.swift` | launch, appearance (`--no-reminders` `:35,62,96`) | — |

### Watch unit — `SingleThreadWatchTests/` (Swift Testing)
Runs: `scripts/test.sh:280-283` (sequential); CI `ci.yml:431-438` against the fresh unpaired watch, pinned `id=`. In `SingleThreadWatch.xcscheme` Testables; **not** in root `.swiftlint.yml` `included` (unformatted? no — is formatted at `scripts/test.sh:198,203`; SwiftLint skipped).

| File | Covers | Notes |
|---|---|---|
| `WatchSyncPipelineTests.swift` | push includes all seven keys, receive saves + fires hooks, absent-key no-op | private `WatchFakeSession: SkipSyncSession` `:9` ("cannot be imported across test bundles"); `.standard` UUID keys; runs on watchOS simulator |
| `WatchAppViewModelTests.swift` | `--ui-testing-glow` seam extends glow duration to 2.0 s | `WatchAppViewModel(arguments: ["--ui-testing-glow"])` `:21-25` |
| `ShowCompletionGlowStateTests.swift` | glow state, `--ui-testing-glow`/`--ui-testing-glow-disabled` force over persisted `false` | `defer { UserDefaults.standard.removeObject }` cleanup `:34,55,67,136,209,241` |
| `ShowEnableActionButtonsStateTests.swift` | default-off, round-trip, group persistence, init read | **writes/clears both `AppGroup.defaults` and `.standard`** (`:7-10,57-61`) because AppGroup falls back |
| `ReminderStoreWatchTests.swift` | watch-side complete/delete/skip/reschedule semantics | `InMemoryEventStore` + `.standard` seeds; `defer` cleanup `:32` |

### Watch UI — `SingleThreadWatchUITests/` (XCTest)
Runs: `scripts/test.sh:269-275` (after runner-framework fix `:262-263`); CI `ci.yml:420-429` (+ `-retry-tests-on-failure`). In root SwiftLint included list (`.swiftlint.yml:9`); SwiftFormat included.

| File | Covers | Notes |
|---|---|---|
| `SingleThreadWatchUITests.swift` | tap reveals confirmation dialog; `testAccessibilityAudit` | `["--ui-testing"]` `:11,:32` |
| `SingleThreadWatchUITestsFlows.swift` | card title/notes, complete, skip→all-done, delete-via-dialog, excluded list, live exclusion, action menu, `--ui-testing-gated` upgrade prompt, glow | flags: priority `:27`, excluded-list `:41`, live-excluded `:60`, action-menu `:112,136,161`, skip-count `:191`, gated `:264`, glow `:284`; shared `launchApp()` helper `:319` |
| `SingleThreadWatchUITestsLaunchTests.swift` | launch | `["--ui-testing"]` `:17` |

### Notable non-target methods
- `scripts/count_tests.sh` — counts `@Test` per suite (`unit_watch # 36` `:11`), `#expect`/`#require`, `.launch()` calls (`launches_watch # 11` `:20`).

## 4. Sync/persistence contract (for any watch-shared value)

- Every value shared with the watch **must** round-trip through `AppGroup.defaults` (the `UserDefaults(suiteName:)` suite), never `UserDefaults.standard` — on simulator the suite always exists, so the two silently diverge (`AGENTS.md:53-57`). Includes `--ui-testing`/`--seed` seams.
- On the watch the group is unregistered → `AppGroup.defaults === UserDefaults.standard` (`AppGroup.swift:16-17`; `PendingCompletionStore.swift:8-9`).
- `UITestingSeed.resetPersistedState()` clears the 24 `persistedKeys` from **both** containers (`UITestingSeed.swift:62-68,73-97`); single caller `AppViewModel.swift:275` (`--seed` only).
- Sync = latest-wins application context (`SkippedReminderSyncService.swift:200-243`), replacement-not-union receive (`:390-394`), `sendMessage` relays for complete/delete/reschedule (`:244-292`).
- iOS sync service guard: built only when `WCSession.isSupported() && !usesInMemoryStore` (`AppViewModel.swift:360`).
- Watch sync-service stores explicitly `.standard` (`WatchAppViewModel.swift:232-244`).