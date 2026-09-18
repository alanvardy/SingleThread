# Conventions — SingleThread (VAR-1044 research appendix)

Reference for Design/Structure/Plan. Line refs are to files under the worktree
root; see `research.md` for the deep dives behind these.

## Canonical commands

- **Full gate (CI-identical)**: `./scripts/test.sh` — formats, lints, builds,
  runs Periphery, then unit + UI tests. Run ONCE at gate time via the
  `run-gate` skill (dedicated async gate subagent in a managed worktree),
  never `nohup` ad hoc.
- **Make targets** (`Makefile`): `build` `test` `ui-test` `watch-build`
  `watch-test` `watch-ui-test` `mac-build` `mac-test` `mac-run`
  `mac-distribute` `simverify` `lint` `format` `periphery` `clean` `check`
  `coverage(-ui/-all)` `reset-storekit`. Pin a simulator with `SIM=`.
- **Fast pre-commit pair**: `make format` then `make lint` (SwiftLint runs
  `--strict` in CI — every warning is an error).
- **Single unit test**: `scripts/test-one.sh <Target/Suite/case>` — exits
  non-zero on a zero-case match (guards a silent red-pass). Must pin the
  destination via `SIM=`.
- **Periphery**: `make periphery`; it reads a stale build index after branch
  switches — clean `DerivedData/` and rerun first.
- **Real-device install/launch script (being modified here)**:
  `scripts/run-devices.sh` (`SIM=`-independent; drives `xcrun devicectl`).
  Env: `SCHEME=SINGLETON`, `BUNDLE_ID=app.alanvardy.SingleThread`,
  `CONFIGURATION=Debug`, `DERIVED_DATA=DerivedData`, `RUN_MAC=1`
  (`run-devices.sh:25-29`).

## Test-suite inventory

- **SingleThreadTests** (`SingleThreadTests/`) — Swift Testing (`@Test`, no
  `test`/`testing` name prefix; SwiftFormat would strip it). Covers ReminderStore,
  AppGroup, EntitlementStore, DailyCompletion/CompletionCounter, ReminderSkip,
  sorting, formatting, parsing. Includes macOS-gated `#if os(macOS)` tests
  (three pre-existing macOS EntitlementStoreTests fail locally but are CI-green:
  `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
  `hostStoreKitIsClean`).
- **SingleThreadUITests** (`SingleThreadUITests/`) — XCTest, accessibility
  audit (`testAccessibilityAudit`); SwiftFormat-**excluded** (`--exclude
  SingleThreadUITests`). Driven by the `--seed '<json>'` launch-arg seam
  (backed by `InMemoryEventStore`) for deterministic write-flow UI tests.
- **SingleThreadWatchTests** (`SingleThreadWatchTests/`) — Swift Testing;
  `SDKROOT=watchos`, `TARGETED_DEVICE_FAMILY=4`, `WATCHOS_DEPLOYMENT_TARGET=11.0`
  (`project.pbxproj:1112-1147`).
- **SingleThreadWatchUITests** (`SingleThreadWatchUITests/`) — XCTest
  (keep `test…` names), `TEST_TARGET_NAME=SingleThreadWatch`
  (`project.pbxproj:1076,1098`).
- Watch legs are invoked via `Makefile:107-120` and CI `watch-ui-tests` job
  (`ci.yml:247-317`); they are simulator-only — **no real-device watch build/test
  exists anywhere**.

## Build / destination gotchas

- **Destination pinning**: name-only `iPhone 17` is ambiguous across runtimes and
  can hang or resolve to a leftover `Gate iPhone 17` sim. Precedence: explicit
  `SIM=` > worktree `.simulator_id` > shared default. Watch: `WATCH_SIM`
  (`Makefile:8`) is generic; `WATCH_TEST_SIM` (`Makefile:12-21`) pins a concrete
  UDID (name-only destinations normalize to `OS:latest` and can match nothing).
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied` shut down
  sims and kill orphaned `xcodebuild`/`xctest` (see `simulator-pairing` skill).
- **Signing posture**: iOS installs use Automatic signing with no flags; macOS
  builds force `CODE_SIGNING_ALLOWED=NO` (`run-devices.sh:158`, `Makefile:44`,
  `ci.yml:177,187`). Watch legs currently pass **no** signing flags (sim-only).
  Watch target: `CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM=6NWX2DHB9Q`,
  `PRODUCT_BUNDLE_IDENTIFIER=app.alanvardy.SingleThread.watchkitapp`,
  `WKCompanionAppBundleIdentifier=app.alanvardy.SingleThread`
  (`project.pbxproj:941-993`).
- **Product paths**: `DerivedData/Build/Products/Debug-iphoneos/` (iOS),
  `…/Debug/` (macOS), `…/Debug-watchsimulator/` (watch sim, `scripts/test.sh:315`).
  A real-watch build would land in `…/Debug-watchos/` (unverified).
- **App Group / shared store rule**: every value shared with the watch must
  round-trip through `AppGroup.defaults` (`group.app.alanvardy.SingleThread`,
  `AppGroup.swift:11`), never `UserDefaults.standard`; `UserDefaults` is not
  `Sendable` — verify concurrency claims against the compiler.

## Real-device devicectl facts (2026-09-17 probe)

- One **real Apple Watch Ultra** is paired & dev-mode-enabled but currently
  `connection.state:"disconnected"`; identifier `6EF5C1CD-A890-559B-98D5-8F7F5A5A699A`,
  udid `00008301-209B793C010BC02E`. `device install app --device <uuid|ecid|serial|
  udid|name|dns> <path>` and `device process launch --device <…> <bundle-id>` are the
  install/launch surface; `--activate/--terminate-existing/--display` are
  "not supported on all platforms".
