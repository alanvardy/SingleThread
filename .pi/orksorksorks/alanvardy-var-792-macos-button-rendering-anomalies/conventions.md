# Conventions — SingleThread (shared factual appendix)

Companion to `research.md`. Everything here exists so Structure/Plan don't re-open `Makefile`, `scripts/test.sh`, `.github/workflows/ci.yml`, or the `*Tests.swift` set. All refs verified at `1b5c7c4`.

## Canonical commands

From `Makefile` (roots at `Makefile:17-115`):

| Command | Purpose | Ref |
|---|---|---|
| `make build` | iOS sim Debug `build-for-testing`, `-scheme SingleThread` | `Makefile:17-18` |
| `make test` / `make ui-test` | iOS unit / UI suites on `$(SIM)` | `Makefile:75`, `:78` |
| `make mac-build` / `make mac-test` | macOS (`platform=macOS`) build / unit tests | `Makefile:23-24`, `:26-27` |
| `make watch-build` / `watch-test` / `watch-ui-test` | watchOS build / single suites | `Makefile:20-21`, `:92-98`, `:84-90` |
| `make lint` | `swiftformat --lint` all dirs + `swiftlint lint --strict` | `Makefile:106-108` |
| `make format` | `swiftformat` all dirs + `swiftlint --fix` | `Makefile:110-111` |
| `make periphery` | `periphery scan --strict` | `Makefile:114-115` |
| `make simverify` | manual-verification iOS screenshots via `scripts/simverify.sh` (runs `SingleThreadUITestsAppearanceLaunchTests`) | `Makefile:81-82` |
| `make check` | alias over the make flow | `Makefile:100` |

**Full gate — `./scripts/test.sh`** (identical to CI; `set -euo pipefail` `:2`). Pipeline order (full mode, `:195-299`):
1. `swiftformat` + `swiftlint --fix` (`:198-199`)
2. `swiftformat --lint` (`:201-203`)
3. `swiftlint lint --strict` (`:205-206`)
4. iOS sim build (`:208-216`) then watch build `generic/platform=watchOS Simulator` (`:218-220`)
5. `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` (`:222-227`)
6. Unit tests `-only-testing:SingleThreadTests` on iOS (`:237`), UI tests `-only-testing:SingleThreadUITests` (`:245`), watch UI + watch unit (`:250-255`), macOS unit tests (`:288-292`)
7. `UNIT_ONLY=1` / `UI_ONLY=1` skip earlier stages and run just unit (`:299-313`) or UI (`:322-340`).

Destinations (`scripts/test.sh:5-12`; mirrored in `Makefile:1-8`): `SIM` (default `iPhone 17`), `WATCH_TEST_SIM` (`Apple Watch Series 11 (46mm)`), `MAC_SIM=platform=macOS`.

## CI structure (`.github/workflows/ci.yml`)

- iOS unit tests matrixed over `device: ["iPhone 17", "iPad (A16)"]` (`ci.yml:25-27`); UI tests in 3 disjoint groups split by `-only-testing:` fragments (`ci.yml:13-18`, groups at `:125-199`, `:213-260`) — the per-group split exists because 5 UI classes are too long for one runner.
- **mac-tests job** runs the same `-only-testing:SingleThreadTests` on `platform=macOS` (`ci.yml:271-312`, command `:296-312`) — unit tests execute on iOS AND macOS.
- **UI tests run only on iOS simulators in CI — never macOS.**
- Watch jobs create a fresh paired sim (UDID env at `ci.yml:370-438`).
- Lint job: `swiftformat --lint` + `swiftlint lint --strict` (`ci.yml:350-354`); Periphery job (`:367`).

## Test-suite inventory

### `SingleThreadTests/` (Swift Testing — `@Test`, `import Testing`) — iOS + macOS
Platform gating style: per-test or whole-file `#if os(...)` — the same test binary runs on both platforms, so gates compile differently per platform.

Whole-file `#if os(iOS)`:
- `BackgroundCardTests.swift:8-147` — row scaffold clears, `CardPlate` fills/corner radius, fake `SpeechTranscribing`.
- `ActionButtonTests.swift:8-134` — `ContentViewModel.showsActionButtons` gate decision (seam, not UI).

Per-test/per-block gating:
- `SettingsViewTests.swift` — macOS gates at `:69,123,158,189,219,273,292,330`; iOS gates at `:66,78,100,112`. Asserts `SettingsSubscreenLayout` presence only on macOS.
- `AppearanceModeTests.swift` — `#if os(iOS) import UIKit` `:5-7` / `#if os(macOS) import AppKit` `:8-10`; asserts per-platform mapping values (`:18-40`).
- `SingleThreadTests.swift` — macOS-only copy assertions (`:44-47` vs `:48-50`, `:61-68`); macOS refresh-button reflected signature (`:73-96`).
- `MicrophoneToggleTests.swift` — iOS-gated tests at `:232`, `:270`.
- `EnableActionButtonsSyncTests.swift` — whole-file `#if os(iOS) || os(watchOS)` `:1`.
- Settings/platform-neutral files: `SwipePromptTests.swift`, `CardPlateTests.swift`, `CardPlateModifierTests.swift`, `ColorCrossPlatformTests.swift`, `SettingsSubscreenLayoutTests.swift` (asserts both directions — no-op on iOS `:25-34`, applied on macOS `:13-21`), `AboutViewTests.swift`.

Appearance/button-relevant tests to reuse: `SwipePromptTests.swift` (reflection, prompts+plate composition), `CardPlateTests.swift`/`CardPlateModifierTests.swift` (constants+modifier chain), `BackgroundCardTests.swift` (iOS-gated decision asserts), `ActionButtonTests.swift` (iOS toggle gate), `SingleThreadTests.swift:73-96` (macOS button signature), `AppearanceModeTests.swift` (appearance mappings), `ColorCrossPlatformTests.swift:9-11` (only asserts description non-empty).

### `SingleThreadUITests/` (XCTest — `test...`, a11y audit) — iOS only in CI, macOS `#else` compiled but never run
- `SingleThreadUITestCase.swift` — `launchApp`/`launchSeeded`/flip helper/`statusLabel` (`:13-63`); seams `--ui-testing`, `--seed '<json>'`, `--no-reminders`/`--ui-testing-notifications`/`--url-opener-spy`.
- `ActionButtonsUITests.swift` — button existence, `runsForEachTargetApplicationUIConfiguration = false` `:6-13`, audit split `#if os(iOS)` `:70-73` vs `#else` `:74-75`.
- `SingleThreadUITests.swift` — `testAccessibilityAudit` `:27-66`: iOS splits on `CI` env `:53` (CI `[.sufficientElementDescription, .trait]`, local + `[.dynamicType, .hitRegion]` `:58-60`); macOS `#else` default audit `:62-64`.
- `SingleThreadUITestsAppearanceLaunchTests.swift` — activation + screenshots only (no value assert; doc `:48-57`); `runsForEachTarget...= false` `:15-21`.
- `SingleThreadUITestsFlows.swift` — `--seed` driver, glow/nudge seams, upgrade geometry assertion (`:681-697`).
- `NotificationsUITests.swift` / `NotificationSchedulingUITests.swift` — whole-file `#if os(iOS)` `:1`/`:113`, `:1`/`:135`.

### `SingleThreadWatchTests/` (Swift Testing) — `ReminderStoreWatchTests`, `ShowCompletionGlowStateTests`, `ShowEnableActionButtonsStateTests`, `WatchAppViewModelTests`, `WatchReminderViewRegressionTests`, `WatchSyncPipelineTests`
### `SingleThreadWatchUITests/` (XCTest) — `SingleThreadWatchUITests.swift`, `SingleThreadWatchUITestsFlows.swift`, `SingleThreadWatchUITestsLaunchTests.swift` (requires paired watch+phone sim; `scripts/test.sh:250-255`)

## Build & verify gotchas

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** set on iOS app and watch app targets only — not `SingleThreadCore`/widget/test targets; async functions in app targets are `@MainActor` by default.
- **Swift 6 language mode** (`SWIFT_VERSION = 6.0`) with `SWIFT_APPROACHABLE_CONCURRENCY = YES`.
- **Warnings are errors** (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`) — every `swiftlint lint --strict` warning fails.
- **Unit-test names must NOT start with `test`** — SwiftFormat strips/renames them (`make format` causes phantom diffs); UI-test (XCTest) names keep `test…` and `SingleThreadUITests` is SwiftFormat-excluded.
- **Destination pinning required**: bare `name=iPhone 17` is ambiguous with multiple runtimes — `scripts/test.sh:22-27` resolves to a concrete UDID and pre-boots (`:40-44`). CI does the same (`ci.yml:48-52`in comment).
- **One xcodebuild test process at a time** (simulator contention); on `Busy`/`RequestDenied` shutdown sims and kill orphaned xcodebuild/xctest.
- **Watch UI tests need a paired sim** (`xcrun simctl pair`); local machine needs `lib_TestingInterop.dylib` embedded into the watch UI-test runner (`scripts/test.sh:257-267`) — CI's runtime has it.
- `scripts/test.sh` prunes stale XCTestDevices runtimes older than `RUNTIME_AGE_HOURS` (`:16-18,101-105`).
- **Deployment-target consistency guard** in `scripts/test.sh:106-193`: iOS 18.7, macOS+watchOS 26.5, Package.swift literals — a failing guard aborts the gate.
- **Periphery** scans the derived-data index store (`make periphery` uses `-destination`, full gate uses `--skip-build --index-store-path`).
- `--seed '<json>'` seam (backed by `InMemoryEventStore`) is the deterministic UI-test driver for write flows; all shared-with-watch values must round-trip via `AppGroup.defaults` (never `UserDefaults.standard`) — see `AppViewModel.makeStore` (`AppViewModel.swift:250-286`).

## Naming / style

- SwiftLint `identifier_name` ≥ 3 chars (exceptions: `id`, `e`, `d`, `rt`, `to`, `gvm`) — watch out when naming plate/glyph locals.
- Force-unwrapping banned outside test code; fixtures relax via `SingleThreadTests/.swiftlint.yml`.

## Key facts for Structure/Plan (from research.md)

- No custom `ButtonStyle` structs exist; `.controlPlate()` styles the button **label** and leaves the platform default style's chrome active → macOS default bezel + 56×56 plate is the suspected anomaly surface.
- `UpgradePromptButton` is the only `.buttonStyle(.plain)` + fully hand-drawn button (`PurchaseSettingsView.swift:175-197`).
- Style constants live in `CardPlate` enum (`CardPlate.swift:16,23,29-30`) exactly so tests can assert them; plate modifiers take resolved colors (`CardPlateModifier.swift:8-15`).
- Runtime appearance is window-level (UIWindow `overrideUserInterfaceStyle` / NSWindow `.appearance`); SwiftUI color-scheme modifiers only in `#Preview`.