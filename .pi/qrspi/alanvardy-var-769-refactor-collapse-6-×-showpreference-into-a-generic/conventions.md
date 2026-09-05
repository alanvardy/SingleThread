# Conventions — Shared Factual Appendix

Companion to `research.md`. All commands/paths repo-relative; line refs verified against the working tree.

## 1. Canonical commands

From `Makefile` and `scripts/test.sh` (CI mirrors in `.github/workflows/ci.yml`):

| Command | What it runs | file:line |
|---|---|---|
| `make build` | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing` (CPU arch defaults to an Intel simulator; `SIM` default `platform=iOS Simulator,name=iPhone 17`) | `Makefile:1,17-18` |
| `make test` | `./scripts/test.sh --unit-only` | `Makefile:75-76` |
| `make ui-test` | `./scripts/test.sh --ui-only` | `Makefile:78-79` |
| `make check` | `./scripts/test.sh` (full CI-identical gate: format lint, build, Periphery, unit + UI tests) | `Makefile:104-105` |
| `make watch-build` | build `SingleThreadWatch` scheme on `generic/platform=watchOS Simulator` | `Makefile:20-21` |
| `make watch-test` / `make watch-ui-test` | `-only-testing:SingleThreadWatchTests` / `SingleThreadWatchUITests` with `WATCH_TEST_SIM` (default `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)`) | `Makefile:85-96` |
| `make mac-test` | macOS-scheme unit tests (`CODE_SIGNING_ALLOWED=NO`, `-only-testing:SingleThreadTests`) | `Makefile:27-28` |
| `make lint` | `swiftformat --lint` over 8 dirs then `swiftlint lint --strict` | `Makefile:106-108` |
| `make format` | `swiftformat` over 8 dirs then `swiftlint --fix` | `Makefile:110-112` |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` (scans build's index store; `.periphery.yml`) | `Makefile:114-115` |
| `make coverage` / `coverage-ui` / `coverage-all` | xccov result bundles (unit / UI / combined) | `Makefile:47-73` |
| `SIM=…` | overrides the iOS simulator destination (`scripts/test.sh` accepts the same via env) | `Makefile:1` |

`scripts/test.sh`: resolves a name-only `SIM` to its concrete UDID (`xcrun simctl list devices available`, `scripts/test.sh:22-31`) and pre-boots the sim (`:33-36`), then prunes stale `~/Library/Developer/XCTestDevices` runtimes older than `RUNTIME_AGE_HOURS=1` (`:38-70`). CI matrix devices: `["iPhone 17", "iPad (A16)"]` with the same UDID resolution; iOS UI tests are split across three disjoint `-only-testing` groups (LaunchTests+AppearanceLaunch / Flows / SingleThread+ActionButtons) — `.github/workflows/ci.yml:13-27`.

## 2. Test-suite inventory

- **`SingleThreadTests/`** (Swift Testing; iOS/macOS; `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` — `pbxproj:856,885`). 60 files. Preference-layer-relevant:
  - `Show{Date,List,Recurrence,Alarms,CompletionGlow}PreferenceTests.swift` — per-preference absent-fallback + round-trip, UUID key on `.standard` (no `ShowUndatedRemindersPreferenceTests.swift` — that struct is covered only via sync tests).
  - `Show{Date,Alarms,Recurrence}Tests.swift` — `ReminderCardView` render gates; `CompletionGlowTests.swift` — glow state machine + `CompletionGlowViewModelTests` (pref-disabled/enabled cases `:83-105`).
  - `SortOptionTests.swift` (incl. `SortOptionStoreTests` `:39-61`), `ExcludedListStoreTests.swift`, `SkipCountStoreTests.swift`, `CompletionCounterStoreTests.swift` (serialized, `:5`), `PendingCompletionStoreTests.swift` (+`PendingCompletionLogicTests.swift`), `ReminderSkipTests.swift` (logic only — the store's load/save is tested indirectly).
  - `SkippedReminderSyncServiceTests.swift` — `#if os(iOS) || os(watchOS)` (`:1`), `FakeSession` fake (`:9-28`); `EntitlementSyncTests.swift` (reuses target-level `FakeSession`).
  - Others: `ReminderStoreTests.swift` (serialized subsuites `:15,511,720,898`), `EventKitStoringTests.swift`, `ReminderStoreGateTests.swift`, `ContentViewModelTests.swift` (init injection incl. glow pref), `SettingsViewModelTests.swift`, `SettingsViewTests.swift` (bag defaults + row assertions), `UITestingSeedTests.swift`, `AppGroupTests.swift`, `ResumptionGateTests.swift`.
- **`SingleThreadWatchTests/`** (Swift Testing; watchOS; **not** in root `.swiftlint.yml` `included`). 5 files:
  - `ShowCompletionGlowStateTests.swift` — `@Suite(.serialized)` `:27`, real `.standard` key `"showCompletionGlow"`, launch-arg param tests `:48-51`; the only state-holder suite.
  - `WatchSyncPipelineTests.swift` — private `WatchFakeSession` `:9-25` (cannot import iOS bundle's fake), `makePreference`/`makeService` relaunch seam `:411-455`, `receivedPreferenceSurvivesRelaunch` `@Test(arguments:)` `:157-164`.
  - `ReminderStoreWatchTests.swift` (serialized `:26`), `WatchAppViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`.
- **`SingleThreadUITests/`** (XCTest; iOS; SwiftFormat-excluded via `.swiftformat:21`; `.swiftlint.yml` applies). 10 files: `SingleThreadUITestsFlows.swift` (toggle-persistence + glow tests `:419-512`), `SingleThreadUITestsLaunchTests.swift`, `SingleThreadUITestsAppearanceLaunchTests.swift`, `ActionButtonsUITests.swift`, `Notifications*/SkipNudge*/NotificationSchedulingUITests.swift`, helper `SingleThreadUITestCase.swift` (`launchApp`/`launchSeeded`/`flipToggle`/`assertTogglePersists`).
- **`SingleThreadWatchUITests/`** (XCTest; watchOS): `SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift`. Behavior driven by launch args, not toggles.
- **`SingleThreadWidget/`**: no test bundle.

## 3. Build/verify gotchas

- **Destination pinning**: name-only `iPhone 17` is ambiguous with multiple runtimes — a bare `name=` destination hangs; pin `,OS=` or `,id=` (`scripts/test.sh:22-31`; AGENTS). `scripts/test.sh`/`Makefile` accept `SIM=`.
- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied`: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`. Watch UI tests need a concrete device (`WATCH_TEST_SIM`) and a paired sim: `xcrun simctl pair <watchUDID> <phoneUDID>`.
- **Warnings are errors** project-wide (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`, Debug+Release) except `SingleThreadTests` — scope overrides in pbxproj, never CLI flags.
- **SwiftLint `--strict`**: every warning fails (35 opt-in rules incl. `force_unwrapping`, `accessibility_label_for_image`, `accessibility_trait_for_button`, `unhandled_throwing_task`, …; `line_length` 120/150; default `identifier_name` min 3 — only exclusions id/e/d/rt/to/gvm; default `function_body_length` 50/100). `force_unwrapping` is disabled only in `SingleThreadTests/.swiftlint.yml`; `SingleThreadWatchTests` is not linted at all.
- **SwiftFormat**: `preferSwiftTesting` strips `test`/`testing` prefixes — Swift-Testing unit-test names must not start with them (phantom "file reverted" diffs under `make format`). UI tests are SwiftFormat-excluded.
- **Unit tests use Swift Testing** (`import Testing`, `@Test`); UI tests use XCTest (`test…` names). New logic ships with unit **and** UI coverage; bug fixes add a reproducing test first.
- **`AppGroup.defaults` vs `.standard` diverge on simulator** (the suite always exists there) — every persisted value shared with the watch must round-trip the App Group suite, including `--ui-testing`/`--seed` seams (`UITestingSeed.swift:59-75` wipes both containers).
- **`--seed <json>`** (backed by `InMemoryEventStore`) is the standard deterministic iOS UI-test write-flow seam; watchOS uses its own `--ui-testing` seam (`WatchAppViewModel.swift:94-155`).
- **Periphery** scans the build's index store — run after a build, with `--strict` (`.periphery.yml`).
- **New test targets** require pbxproj object IDs, scheme TestAction, `-only-testing` entries in `scripts/test.sh`, and CI matrix entries — not a plain file add.