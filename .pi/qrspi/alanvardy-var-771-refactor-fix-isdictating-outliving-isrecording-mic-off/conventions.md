# Conventions — Shared Factual Appendix

Dense reference for Design/Structure/Plan. All line numbers are working-tree `cat -n` values.

## 1. Canonical commands

From `Makefile` (targets at the cited lines) and `scripts/test.sh`:

| Command | What it runs |
|---|---|
| `make build` (`Makefile:17-18`) | `xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug build-for-testing` |
| `make watch-build` (`:20-23`) | Generic watchOS Simulator Debug build |
| `make mac-build` (`:31-33`) / `make mac-test` (`:26-29`) | macOS destination, `CODE_SIGNING_ALLOWED=NO`, units only |
| `make test` (`:75-76`) | `scripts/test.sh --unit-only` |
| `make ui-test` (`:78-79`) | `scripts/test.sh --ui-only` |
| `make check` (`:100-101`) | `./scripts/test.sh` — full gate (identical to CI) |
| `make lint` (`:106-108`) | `swiftformat --lint` (7 dirs) + `swiftlint lint --strict` |
| `make format` (`:110-112`) | `swiftformat` + `swiftlint --fix` |
| `make periphery` (`:114-115`) | `periphery scan --strict -- -destination "$(SIM)"` |
| `make watch-ui-test` (`:84-89`) / `make watch-test` (`:92-97`) | Watch UI / unit tests on concrete `WATCH_TEST_SIM` |
| `make simverify` (`:81-82`) | `scripts/simverify.sh` |
| `make coverage` / `coverage-ui` / `coverage-all` (`:44-72`) | xccov result bundles under `build/` |

- **`SIM` default** = `platform=iOS Simulator,name=iPhone 17` (`Makefile:11`); override `SIM='platform=iOS Simulator,id=<UDID>'` (name-only is ambiguous with multiple runtimes — pin it). `WATCH_TEST_SIM` defaults to `platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (`Makefile:14-15`); `MAC_SIM = platform=macOS`.
- **`scripts/test.sh`** (`scripts/test.sh`): `MODE` arg `full|--unit-only|--ui-only` (`:87-102`). Full pipeline order: `cleanup_xctest_runtimes` (`:104`, `RUNTIME_AGE_HOURS=1` default) → deployment-target guard `verify_deployment_target` (`:119-191`, called `:193`; iOS 18.7, macOS/watchOS 26.5, 20 pbxproj literals, 3 Package.swift literals) → swiftformat + `swiftlint --fix` (`:197-198`) → `swiftformat --lint` (`:200-204`) → `swiftlint lint --strict` (`:206-208`) → iOS `build-for-testing` (`:210-216`) → watch build (`:218-224`) → `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` (`:226-228`) → iOS unit tests, parallel-testing `YES`, 900 s allowance (`:230-238`) → iOS UI tests (`:240-246`) → watch build-for-testing + **local-only `lib_TestingInterop.dylib` embed into the watch UI runner** (missing on this machine's watchOS 26.5 simruntime; `:258-275`) → watch UI tests (`:278-284`) → watch unit tests (`:278-284` area) → macOS unit tests (`:286-292`).
- **Destination pre-resolution**: `scripts/test.sh:24-51` resolves a name-only SIM to its UDID (`xcrun simctl list devices available`) and pre-boots it (matches CI `ci.yml:48-52`).
- **CI** (`.github/workflows/ci.yml`): `macos-26`, Xcode 26.6 (`:20-31`); **unit tests matrix `device: ["iPhone 17", "iPad (A16)"]`** (`:24-27`), `-maximum-concurrent-test-simulator-destinations 1` (`:77`); UI tests split into disjoint `-only-testing:` groups `UI_GROUP_A/B/C` (`:13-18`) run in a parallel matrix job; per-device sim pre-boot steps (`:116-120`).

## 2. Test-suite inventory

All unit suites are **Swift Testing** (`import Testing`, `@Test`); UI suites are **XCTest**. Test names must not start with `test`/`testing` in unit suites — SwiftFormat strips those prefixes (`make format` silently renames). UI test targets are SwiftFormat-excluded.

### iOS unit tests — `SingleThreadTests/` (62 files; platform-gated runs on iOS + macOS)
- **Dictation**: `ReminderDictationTests.swift` — `FakeSpeechTranscriber` (`:10-66`), `DetachedAuthorizationRequiring` (`:70-90`), auth/timeout/flag-mirror asserts, `DictationViewModel` integration (`:191-207`), `DictationErrorTests` (`:212-232`); `MicrophoneToggleTests.swift` — mic visibility/auth-refresh/scene-phase, rendering via `String(describing:)`, `#if os(iOS)` gate at `:232-244`.
- **Parser/accumulator**: `ReminderDictationParserTests.swift`, `TranscriptionAccumulatorTests.swift`, `ResumptionGateTests.swift`, `CodeSpanFormatterTests.swift`.
- **Store/state (Core)**: `ReminderStoreTests.swift` (`@Suite(.serialized)` `:15,511`; `noopSettle` `:10-12`; continuation rendezvous `:263,275,295,325,526,598,624`), `ReminderStoreGateTests.swift` (`:11` serialized, `:6-8` noopSettle), `InMemoryEventStore`-backed everywhere; `CompletionCounterStoreTests`, `SkipCountStoreTests`, `PendingCompletionStoreTests` (injected clock `:29-40`), `PendingCompletionLogicTests`, `UndoStoreTests`, `EntitlementStoreTests`, `EntitlementSyncTests`, `SkippedReminderSyncServiceTests`, `ExcludedListStoreTests`.
- **UI-state**: `CompletionGlowTests.swift` (serialized `:13`; injected `duration = 0.05` + ≤100×20 ms polling `:26-42`), `ContentViewModelTests.swift` (constructs real `ReminderDictation()`, never transcribes; `:21,40,60,76,94`), `SettingsViewModelTests`, `SettingsViewTests`, `ReminderSkipTests`, `SwipePromptTests`, `UITestingSeedTests`, `ReminderIntentsTests`, `ReminderDeepLinkTests`.
- **Presentation**: `ActionButtonTests.swift` (gate-decision asserts; `:12-16` `_ConditionalContent` reflection limit), `AboutViewTests`, `AppDelegateTests`, `AppearanceModeTests`, `AppGroupTests`, `BackgroundCardTests` (`:18-31` fake transcriber), `BackgroundFadeTests`, `BackgroundImageStoreTests` (only mid-async-window asserts in the suite: `:241-253`, `:315+` via `GatedBackgroundFetcher`; continuation `:459,466`), `BackgroundPhotoLayerTests`, `CardPlateTests`, `CardPlateModifierTests` (`:7-9`), `ColorCrossPlatformTests`, `LocalizationTests` (+`LocalizationTestHelpers`, `StubBundle`), `MinimumDisplayDurationTests`, `PrivacySettingsContentTests`, `ReminderDisplayTests`, `ReminderRecurrenceFormatterTests`, `SettingsCaptionTests`, `ShowAlarmsTests`/`ShowAlarmsPreferenceTests`, `ShowCompletionGlowPreferenceTests`, `ShowDateTests`/`ShowDatePreferenceTests`, `ShowListPreferenceTests`, `ShowRecurrenceTests`/`ShowRecurrencePreferenceTests`, `SingleThreadTests`, `SortOptionTests`, `TextSizeTests`, `URLOpeningTests`, `BackgroundTestFixtures`.
- **Platform gating** (~none whole-file; per-test `#if os(iOS)` / `#if os(macOS)` inside files; e.g. `MicrophoneToggleTests.swift:232-244` is iOS-only, `ActionButtonTests` has macOS variants). The same `SingleThreadTests` target runs on the macOS destination in the gate.

### iOS UI tests — `SingleThreadUITests/` (XCTest, a11y-audited)
`SingleThreadUITestCase.swift`, `SingleThreadUITests.swift`, `SingleThreadUITestsFlows.swift`, `SingleThreadUITestsLaunchTests.swift`, `SingleThreadUITestsAppearanceLaunchTests.swift`, `ActionButtonsUITests.swift`, `NotificationsUITests.swift`, `NotificationsSettingsUITests.swift`, `NotificationSchedulingUITests.swift`, `SkipNudgeUITests.swift`. Includes `testAccessibilityAudit()` (`performAccessibilityAudit`); deterministic write flows use the `--seed '<json>'` launch-arg seam (InMemoryEventStore). CI groups: `UI_GROUP_A` = launch/appearance, `UI_GROUP_B` = Flows, `UI_GROUP_C` = main + ActionButtons (`ci.yml:16-18`).

### watchOS tests
- `SingleThreadWatchTests/` (Swift Testing): `ReminderStoreWatchTests.swift` (`:24` defer-cleanup convention, `:33-91`), `ShowCompletionGlowStateTests.swift` (`:35-130`), `WatchAppViewModelTests.swift`, `WatchReminderViewRegressionTests.swift`, `WatchSyncPipelineTests.swift`.
- `SingleThreadWatchUITests/` (XCTest): `SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift`. Need a **paired** watch+phone sim (`xcrun simctl pair <watchUDID> <phoneUDID>`); concrete `WATCH_TEST_SIM` required.

## 3. Build/verify gotchas surfaced by research

- **One xcodebuild test process at a time** (simulator contention). On `Busy`/`RequestDenied` runner-launch failures: `xcrun simctl shutdown all`, kill orphaned `xcodebuild`/`xctest`.
- **Destination pinning**: bare `name=iPhone 17` hangs with multiple runtimes; pin `,OS=` or `,id=` (resolved automatically in `scripts/test.sh:24-51`, needs manual pinning for ad-hoc `xcodebuild`).
- **Watch UI runner**: this machine's watchOS simruntime lacks `lib_TestingInterop.dylib` — the gate embeds it from Xcode's WatchSimulator platform dir (`scripts/test.sh:258-275`); only applies locally, no-op on CI.
- **App Group vs `UserDefaults.standard`**: every value shared with the watch must round-trip through `AppGroup.defaults` (`UserDefaults(suiteName:)`), never `.standard` — the two diverge silently on simulator. Applies to `--ui-testing`/`--seed` seams too.
- **Unit-test naming**: names beginning `test`/`testing` get renamed by SwiftFormat under `make format` (phantom file-reverted diffs). `force`-unwrap banned outside test code; `SingleThreadTests/.swiftlint.yml` relaxes for fixtures; `--strict` ⇒ every warning fails.
- **Fakes convention**: dictation/speech fakes are `@MainActor private final` classes in-file (per suite), implementing `SpeechTranscribing`; `MicToggleFakeTranscriber` overrides `refreshAuthorizationStatus`, the rest use the protocol default no-op (`ReminderDictation.swift:19-23`).
- **`String(describing:)` render asserts**: work on `view.bottomBar` (shallow) but not deeply on `view.body` (elides `Text` storage); SF Symbols serialize as `NamedImageProvider` — assert on a11y labels, not symbol names (`MicrophoneToggleTests.swift:55-59,190-192`).
- **Synchronization seams**: `ReminderStore(settle:)` injectable (`ReminderStore.swift:38-40`); `noopSettle` for speed; continuation rendezvous on store-hook fires; injected clocks instead of sleeps; `@Suite(.serialized)` where UserDefaults/global state is touched; `defer { removeObject }` UserDefaults cleanup everywhere.
- **Concurrency**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on app+watch targets (do **not** wrap in `Task { @MainActor in }` there); SingleThreadCore/widget/tests need explicit `@MainActor`; Swift 6 language mode; warnings-as-errors both configs.
- **Gate staging**: phase subagents run a build + targeted `-only-testing:` suites only; the full `./scripts/test.sh` runs **once** by the parent after phases commit (~multi-hour).