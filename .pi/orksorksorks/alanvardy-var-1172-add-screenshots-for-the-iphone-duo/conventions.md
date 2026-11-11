# Conventions & Factual Appendix

Shared reference for Design / Structure / Plan. Dense; every item cites
`file:line`. All line numbers verified on branch
`alanvardy-var-1172-add-screenshots-for-the-iphone-duo` unless a branch is named.

## Canonical commands

| Purpose | Command | Source |
|---|---|---|
| Unit tests (macOS-native / Swift Testing) | `make test` → `./scripts/test.sh --unit-only` | `Makefile:98`; `scripts/test.sh:305` |
| iOS UI tests (XCTest) | `make ui-test` → `./scripts/test.sh --ui-only` | `Makefile:101`; `scripts/test.sh:320` |
| Full CI-identical gate | `make check` → `./scripts/test.sh` | `Makefile:123` |
| Watch unit tests | `make watch-test` (pins `$(WATCH_TEST_SIM)`) | `Makefile:115` |
| Watch UI tests | `make watch-ui-test` | `Makefile:107` |
| macOS tests | `make mac-test` | `Makefile:46` |
| Build | `make build` | `Makefile:37` |
| Periphery (unused-code scan) | `make periphery` | `Makefile:137` |
| Lint | `make lint` → `swiftformat --lint` + `swiftlint lint --strict` | `Makefile:129` |
| Format | `make format` | `Makefile:133` |
| Sim verification | `make simverify` → `./scripts/simverify.sh` | `Makefile:104` |
| Single unit test (bounded, non-zero on zero-match) | `scripts/test-one.sh <Target/Suite[/case()]>` | repo AGENTS.md |
| Warning-checker self-test | `bash scripts/tests/warning-check/run.sh` (also `scripts/test.sh:237`, CI `ci.yml:261–263`) | Q5 |
| Offline run-devices harness (hand-run, not wired) | `bash scripts/test-run-devices.sh` | `scripts/test-run-devices.sh:1–217` |
| App Store screenshot pipeline | `bash scripts/appstore-screenshots.sh [classes…] [flags]` | `scripts/appstore-screenshots.sh:251–303` |

- Gate prechecks: `verify_deployment_target` + `verify_xcodebuild_wrapped`
  (`scripts/test.sh:222–223`); the latter rejects any bare `xcodebuild` invocation
  in `test.sh` (`:110–121`). All builds must go through `run_xcodebuild <log>`.
- Warnings are errors: `check-warnings.sh` scans build logs with
  `WARNING_PATTERN='^[^:]+:[0-9]+:[0-9]+: warning: '` and allowlist
  `scripts/xcodebuild-warnings.allow` (`scripts/check-warnings.sh:22–23`).
- SwiftFormat/`preferSwiftTesting` rename test funcs starting `test`/`testing`
  (unit tests must not use that prefix); UI (XCTest) tests keep `test…`.
- Destination pinning: `SIM=` env; default `iPhone 17` (local), `iPad (A16)`
  also supported; CI matrix runs both. Check `.simulator_id`/`scripts/test-one.sh`.
- One `xcodebuild` test process at a time; watch UI tests need an unpaired watch
  pinned by UDID (`WATCH_TEST_SIM='platform=watchOS Simulator,id=<udid>'`).

## Test-suite inventory (branch 1172 HEAD)

| Path | Count / type | Gate coverage |
|---|---|---|
| `SingleThreadTests/` | 102 files, Swift Testing (`import Testing`, `@Test`) | `make test` / `test.sh --unit-only` |
| `SingleThreadUITests/` | 1 file, XCTest (a11y audit; SwiftFormat-excluded) | `make ui-test` / `test.sh --ui-only` |
| `SingleThreadWatchTests/` | 14 files, Swift Testing | watch-unit stage in `scripts/test.sh` |
| `SingleThreadWatchUITests/` | 1 file, XCTest | watch-UI stage in `scripts/test.sh` |
| macOS unit | run via `make mac-test` / `test.sh` macOS stage | known local-only failures: three `EntitlementStoreTests` (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` canary) |
| `scripts/tests/warning-check/` | shell fixtures + `run.sh` | wired at `scripts/test.sh:237` |
| `scripts/test-run-devices.sh` | offline bash harness for `run-devices.sh` | **not wired** into gate/Makefile/CI |
| `scripts/appstore-screenshots.sh` | — | **no test**; runtime `sips` size allowlist only (`:710–730`) |

Platform gating: unit tests are macOS-native under `make test`; iOS/watch
build+test legs run only in the full gate. `scripts/test-run-devices.sh`
covers only the iOS/watch *discovery* filters (hardware install/launch out of
scope, header `:1–9`).

## Build / verify gotchas

- **Shell**: the command tool runs fish; wrap bash bodies as `bash -c '…'` or
  `bash /tmp/x.sh`. A `fish:`/`fish-guard` rejection aborts the line — do not
  retry a variant.
- **Duo code is unmerged**: `DuoDisplay`/`DuoOuterPortrait`/`ChecklistLayout`
  exist only on `alanvardy-var-1170-increase-width-on-outer-duo-screen`
  (PR #247 OPEN), not on HEAD or `origin/main`. Do not assume they are present.
- **No Duo simulator device type**: `xcrun simctl list devicetypes` has no
  foldable/Duo entry; the Duo is physical (`iPhone19,4`).
- **Screenshot pipeline is simulator-only** (`appstore-screenshots.sh` uses
  `simctl` throughout, `DESTINATION='generic/platform=iOS Simulator'` `:138`);
  the physical path is `run-devices.sh` via `devicectl`.
- **Screenshot size gate is a hard allowlist** (`:716`):
  `1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496`; a new class's pair
  must be added or the run exits 1 (`:723–726`).
- **No orientation handling** in the screenshot script; **no orientation/
  display forcing launch argument** exists in the app.
- **Wallpaper slots are per class × screen** and every slot the run touches must
  resolve in `prepare_wallpaper` (`:477–511`) or the run errors (exit 3/4 in
  `stage_slot` `:429–461`).
- **App Group invariant**: values shared with the watch must round-trip through
  `AppGroup.defaults` (single cached instance), never `UserDefaults.standard`.
  Note `allowsLandscape` currently lives in `UserDefaults.standard`
  (`OrientationPreference.swift:1–8`) — it is not watch-shared.
- `AppGroup.defaults` must be one cached instance (`AppGroupTests.defaultsIsAStableInstance`).
- Force-unwrap banned outside tests; `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`
  project-wide (per-target overrides only, never CLI flags).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the iOS + watch app targets
  only (not Core/widget/tests).
- Never `git stash` to baseline a failure — use `git show origin/main:<path>`
  or a throwaway worktree.

## Key file/line anchors (current branch)

- Screenshot script: `scripts/appstore-screenshots.sh` (730 lines).
  Config `135–161`; helpers `163–228`; `SCREENS` `234–242`; `DEVICE_TYPES`
  `244–250`; CLI `253–303`; `resolve_udid` `305–321`; wallpapers `323–513`;
  capture `515–595`; watch `597–653`; run/verify `655–730`.
- Wallpaper fixtures: `scripts/fixtures/appstore-wallpapers/` (10 `.jpg` + `manifest.json`).
- Wallpaper consumer: `SingleThread/BackgroundImageStore.swift:55,83–89,215–219`.
- Launch args: `SingleThread/LaunchArgument.swift:18,27`; `AppViewModel.swift:245–321`;
  `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:58–68,113–183`.
- Orientation: `SingleThread/AppDelegate.swift:32–47,51–56`;
  `SingleThreadCore/.../OrientationPreference.swift:1–8,21,24–26`.
- Physical device tooling: `scripts/run-devices.sh`; fixture
  `scripts/fixtures/devicectl-devices.json` (`Fixture iPhone Duo` `:261–269`);
  harness `scripts/test-run-devices.sh`.
- Duo layout (branch `alanvardy-var-1170-…`): `SingleThread/DuoDisplay.swift:4–12`,
  `SingleThread/DuoOuterPortrait.swift:4–39`, `SingleThread/ChecklistLayout.swift:8,21–34`,
  `SingleThread/ContentView.swift:160–162`, tests under `SingleThreadTests/Duo*`.
