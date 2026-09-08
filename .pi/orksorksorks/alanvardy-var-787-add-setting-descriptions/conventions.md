# Conventions — verified commands, test inventory, gotchas

Shared factual appendix for Design/Structure/Plan. All paths relative to repo root; line numbers verified against the working tree.

## Build / test / lint / format / verify commands

### Makefile targets (`Makefile`)
| Command | Runs |
|---|---|
| `make build` | iPhone-sim Debug `build-for-testing` (`Makefile:26-28`) |
| `make test` | `./scripts/test.sh --unit-only` (:48-49) |
| `make ui-test` | `./scripts/test.sh --ui-only` (:51-52) |
| `make check` | `./scripts/test.sh` full gate (:71-72) |
| `make watch-build` / `make watch-test` / `make watch-ui-test` | watchOS scheme; UI needs concrete `WATCH_TEST_SIM` (:30-32, :57-67) |
| `make mac-build` / `make mac-test` / `make mac-run` / `make mac-distribute` | macOS (`CODE_SIGNING_ALLOWED=NO` where noted) (:34-44) |
| `make lint` | `swiftformat --lint` all 8 dirs + `swiftlint lint --strict` (:74-77) |
| `make format` | `swiftformat` all 8 dirs + `swiftlint --fix` (:79-82) |
| `make periphery` | `periphery scan --strict -- -destination "$SIM"` (:84-85) |
| `make coverage` / `coverage-ui` / `coverage-all` | xcodebuild with `-enableCodeCoverage YES` + `xccov view` (:46-57 region) |
| `make clean` | xcodebuild clean (:73) |

- `SIM ?= platform=iOS Simulator,name=iPhone 17` default, override with `SIM=` (`Makefile:1`). `macOS` is an explicit `MAC_SIM` destination (not SIM).

### `scripts/test.sh` (the full CI gate; identical local↔CI)
- Modes: `full` (default) / `--unit-only` / `--ui-only` (`scripts/test.sh:74-86`).
- Full order: deploy-target guard → SwiftFormat (write) → SwiftFormat --lint → SwiftLint --strict → iOS build-for-testing → watchOS build → Periphery (`--skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict`) → iOS unit tests → iOS UI tests → watch UI tests (with local-only `lib_TestingInterop.dylib` copy into the runner, :166-176) → watch unit tests → macOS unit tests (`CODE_SIGNING_ALLOWED=NO`) (:104-200).
- Deployment-target guard: enforces IPHONEOS 18.7, MACOSX/WATCHOS 26.5 across all 20 pbxproj literals + 3 Package.swift platform literals; count drift fails (:38-100).
- Resolves a name-only SIM to a concrete UDID and pre-boots the sim before any mode (:22-37, mirrors `ci.yml:48-52`); cleans stale XCTest runtimes under `~/Library/Developer/XCTestDevices` older than `RUNTIME_AGE_HOURS`.

### CI (`.github/workflows/ci.yml`, Xcode 26.6, `macos-26`)
- **unit-tests** job: matrix `["iPhone 17", "iPad (A16)"]` (:24-25).
- **ui-tests** (Group B = `SingleThreadUITestsFlows`), **ui-tests-launch-appearance** (Group A = `SingleThreadUITestsLaunchTests` + `SingleThreadUITestsAppearanceLaunchTests`), **ui-tests-audits** (Group C = `SingleThreadUITests` + `ActionButtonsUITests`): each matrixed on both devices; `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -retry-tests-on-failure` (comment: iOS simulator clone lockdownd race, :137-146).
- **mac-tests** job: macOS unit tests only (:281-300).
- **lint** job (:302+).
- ⚠️ The three notification UI classes (`NotificationsUITests`, `NotificationsSettingsUITests`, `NotificationSchedulingUITests`) are in **no** CI group — see research.md Open Areas. Local `./scripts/test.sh` full run does cover them (whole-target `-only-testing:SingleThreadUITests`).

## Test-suite inventory

### Platform gate rules
- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; `DEBUG_INFORMATION_FORMAT = dwarf` (Debug) / `dwarf-with-dsym` (Release).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on app/watch targets only — **not** Core package, widget, or test targets (annotate `@MainActor` explicitly there; test structs are `@MainActor`).
- Unit tests (Swift Testing, `SingleThreadTests`): names must NOT start with `test`/`testing` (SwiftFormat strips them).
- Force-unwrapping banned outside tests; relaxed in `SingleThreadTests/.swiftlint.yml`.

### `SingleThreadTests` (Swift Testing, `bundle.unit-test`, `project.pbxproj:268-290`)
Settings-relevant files (full inventory on disk; ~40 files):
- `SettingsViewTests.swift` — body-substring assertions for root + 6 sub-screens (see research.md Q5).
- `SettingsViewModelTests.swift` — smoke: init + `allowsLandscapeChanged` + `showPreferenceChanged` no-crash; `#if os(iOS)` mutations :17/:21.
- `Show{Alarms,Date,List,Recurrence,CompletionGlow}PreferenceTests.swift` — per-pref UserDefaults round-trip; `ShowListPreferenceTests` is the only "disabled default" case.
- `Show{Alarms,Date,List,Recurrence}Tests.swift` — card-layer rendering of the same prefs.
- `LocalizationTests.swift` — four `@Test`s over all four catalogs + InfoPlist.strings (see research.md Q4).
- `LocalizationTestHelpers.swift` — `String.en(_:bundle:table:)` (locale-pinned), `Bundle.core`.
- `PrivacySettingsContentTests.swift`, `AppGroupTests.swift`, `EntitlementStoreTests.swift`, `BackgroundImageStoreTests.swift`, `ExcludedListStoreTests.swift`, `UITestingSeedTests.swift`, `ReminderRecurrenceFormatterTests.swift`, `SwipePromptTests.swift`, etc.

### `SingleThreadUITests` (XCTest, `bundle.ui-testing`, `project.pbxproj:292-314`)
| File | Contents |
|---|---|
| `SingleThreadUITestCase.swift` | base class; `launchSeeded` (`--seed`), `launchApp(arguments:)` :18-26, `flipToggle` :28-41, `assertTogglePersists` :45-54 |
| `SingleThreadUITestsFlows.swift` | 20+ flows incl. settings persistence (:185-713) |
| `NotificationsSettingsUITests.swift` | toggle + interval picker rows (no `#if`) |
| `NotificationsUITests.swift` | full notification flow + a11y audit (`#if os(iOS)` at :1) |
| `NotificationSchedulingUITests.swift` | scheduling seams (`#if os(iOS)` at :1) |
| `SingleThreadUITestsAppearanceLaunchTests.swift` | appearance runtime toggle (`--no-reminders`) |
| `SingleThreadUITestsLaunchTests.swift`, `SingleThreadUITests.swift`, `ActionButtonsUITests.swift` | launch/a11y/action-button suites |

### watch targets
- `SingleThreadWatchTests/` (unit, 5 files: ReminderStoreWatchTests, ShowCompletionGlowStateTests, WatchAppViewModelTests, WatchReminderViewRegressionTests, WatchSyncPipelineTests).
- `SingleThreadWatchUITests/` (3 files). Watch UI tests need a **paired** sim (`xcrun simctl pair <watchUDID> <phoneUDID>`), a concrete `WATCH_TEST_SIM`, and the local `lib_TestingInterop.dylib` workaround (test.sh:159-176) if the simruntime lacks it.

## Gotchas surfaced by research
1. **Destination pinning**: bare `name=iPhone 17` hangs with multiple runtimes; pin `,OS=…`/`,id=<UDID>` or let `scripts/test.sh` resolve+pre-boot. Remote/build CI uses the same resolve pattern (`ci.yml:50-52`).
2. **One `xcodebuild test` process at a time** (simulator contention); CI serializes UI via `-maximum-concurrent-test-simulator-destinations 1`.
3. **`--seed` vs `--ui-testing`**: seeding resets persisted keys; persistence assertions must relaunch with `--ui-testing` (research.md Q5). Seeded write flows don't hit TCC/EventKit.
4. **App Group defaults, not `.standard`**: every watch-synced value must round-trip `AppGroup.defaults` (`AppGroup.swift:8,13-15`); simulators always have the suite, so the two diverge silently.
5. **Catalog edits are manual + 6-language**: new/changed keys must be added to the correct per-target `Localizable.xcstrings`, all six languages `translated`, or `LocalizationTests.catalogsHaveAllSixLanguages` (:63-85) fails. Plural strings need `variations.plural` (one for en/es/de/fr, other-only OK for zh-Hans/ja).
6. **Body-description unit tests** (`SettingsViewTests`) and UI static-text/switch-label matches both assert exact English literals — text changes must keep or update these in lockstep.
7. **Signing**: nothing to sign locally beyond simulator; macOS builds use `CODE_SIGNING_ALLOWED=NO`; CI overrides `DEVELOPMENT_TEAM=` (`ci.yml:37-38`).
8. **Periphery** needs the DerivedData index (`--index-store-path DerivedData/Index.noindex/DataStore` in test.sh; `make periphery` passes `-destination` for a fresh scan).
9. **SwiftFormat `organizeDeclarations`** reorders members on `make format` — harmless, but keep `make format` before `make lint`.
10. **Warnings-as-errors everywhere**: any compiler warning fails the build; no `-suppress-warnings` CLI overrides (conflicts with the SPM package).