# Research Findings — VAR-1044 (run-devices.sh on all devices)

Findings below are from codebase reads (file:line) plus one live `xcrun
devicectl` inventory probe on this machine. Line refs are to files under the
worktree root unless noted.

## Q1: How `scripts/run-devices.sh` flows end to end

**File: `scripts/run-devices.sh`**

- Env defaults (`:25-29`): `SCHEME=SingleThread`, `BUNDLE_ID=app.alanvardy.SingleThread`,
  `CONFIGURATION=Debug`, `DERIVED_DATA=DerivedData`, `RUN_MAC=1`. PID-suffixed temp
  files for device JSON + unreachable log (`:30-31`); `trap … EXIT` removes them
  (`:32`). Product paths (`:34-35`): `APP_PATH=DerivedData/Build/Products/Debug-iphoneos/
  SingleThread.app`, `MAC_APP_PATH=DerivedData/Build/Products/Debug/SingleThread.app`.
  `cd "$(dirname "$0")/.."` (`:37`).
- **iOS discovery** (`:39-93`): `xcrun devicectl list devices -j "$DEVICES_JSON"`
  writes JSON to a file (`:41`; failure → guidance + exit 1 `:42-44`). A python filter
  (`:55-88`) reads `payload["result"]["devices"]` (`:63`) and keeps only devices where
  `hardwareProperties.platform=="iOS"` (`:66`) **and** `deviceType in (iPhone,iPad)`
  (`:68`), `deviceProperties.developerModeStatus=="enabled"` (`:71`; disabled → stderr
  skip `:72`). Unreachable = `connectionProperties.transportType is None` OR
  `properties.connection.state=="unavailable"` OR `connectionProperties.tunnelState=="
  unavailable"` (`:80-82`); unreachable names go to `UNREACHABLE_LOG` (`:83-84`).
  Qualifying entries printed as `identifier|name` (`:86`), consumed by a bash read loop
  into `DEVICES` (`:52-55`).
- Zero-device handling (`:95-107`): any unreachable → error + exit 1 (`:96-98`); none
  found + `RUN_MAC=1` → "macOS run only" (`:100-101`); + `RUN_MAC=0` → exit 1 (`:102-105`).
- Failure tally seeded with unreachable count (`:109-112`).
- **Build leg** (`:115-127`): only if `DEVICES` non-empty; single
  `xcodebuild -scheme SingleThread -destination 'generic/platform=iOS' -configuration
  Debug -derivedDataPath DerivedData build` (`:118-122`); missing `APP_PATH` → exit 1
  (`:124-127`).
- **Per-device install/launch** (`:130-147`): `xcrun devicectl device install app
  --device "$device_id" "$APP_PATH"` (`:136`); `xcrun devicectl device process launch
  --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"` (`:143`); each
  failure increments `failures` (`:137-139,144-145`).
- **macOS leg** (`:151-172`): if `RUN_MAC=1`, build with `-destination 'platform=macOS'`
  **plus `CODE_SIGNING_ALLOWED=NO`** (`:158`, unsigned by design), then `open
  "$MAC_APP_PATH"` (`:167`).
- Summary (`:174-182`): 0 failures → success notice; else `❌ … step(s) failed`, exit 1.
- Legs are **sequential**, not parallel. Only state is the two temp files.

## Q2: SingleThreadWatch target + scheme

**File: `SingleThread.xcodeproj/project.pbxproj`** unless noted

- `PBXNativeTarget` `SingleThreadWatch` (`:316-340`): `productType=com.apple.product-type
  .application` (`:334`), `productName=SingleThreadWatch` (`:335`), product ref
  `SingleThreadWatch.app` at `BUILT_PRODUCTS_DIR` (`:94`), sync dir group `:126-128`,
  package dep SingleThreadCore (`:332-333`).
- Debug settings (`:941-971`) / Release (`:973-1000`): `CODE_SIGN_STYLE=Automatic`,
  `DEVELOPMENT_TEAM=6NWX2DHB9Q`, `GENERATE_INFOPLIST_FILE=YES`,
  `PRODUCT_BUNDLE_IDENTIFIER=app.alanvardy.SingleThread.watchkitapp`
  (`:954,982`), `WKCompanionAppBundleIdentifier=app.alanvardy.SingleThread`
  (`:951,979`), `WKWatchOnly=NO` (`:952,980`), `PRODUCT_NAME="$(TARGET_NAME)"`
  (`:955,983`), `SDKROOT=watchos` (`:956,984`), `SKIP_INSTALL=YES` (`:957,985`),
  `SUPPORTED_PLATFORMS="watchos watchsimulator"` (`:959,987`), `SWIFT_VERSION=6.0`,
  `TARGETED_DEVICE_FAMILY=4` (`:964,992`), `WATCHOS_DEPLOYMENT_TARGET=11.0`
  (`:965,993`).
- Sibling watch test targets same SDKROOT/TDF/DT shape; UITests sets
  `TEST_TARGET_NAME=SingleThreadWatch` (`:1076,1098`).
- **Shared scheme** `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch
  .xcscheme`: BuildAction → `SingleThreadWatch.app` (buildFor* = YES); TestAction(Debug)
  → both watch testables; Launch/Profile(Debug/Release) → `SingleThreadWatch.app`.
  Top-level `SingleThread.xcscheme` also builds the watch (buildForTesting=YES).

## Q3: Identities shared between phone and watch

- App Group suite: `SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:11` =
  `group.app.alanvardy.SingleThread`; suite-backed `UserDefaults` (`:17`) (falls back to
  `.standard`). Entitlement in `SingleThread/AppGroup.entitlements:4-8` (+ on macOS in
  `SingleThread/SingleThread.entitlements:9-13`); `REGISTER_APP_GROUPS=YES` (phone
  `pbxproj:772,822`).
- Companion id = phone `PRODUCT_BUNDLE_IDENTIFIER=app.alanvardy.SingleThread`
  (`pbxproj:770,820`), declared as watch `INFOPLIST_KEY_WKCompanionAppBundleIdentifier`
  (`pbxproj:951,979`). Watch's own bundle id is `…watchkitapp`; widget is `…widget`.
- Phone↔watch sync via WatchConnectivity (`SingleThread/AppViewModel.swift:6,389-410`;
  `SingleThreadWatch/WatchAppViewModel.swift:4,168-200`), sharing many `AppGroup.defaults`
  stores (DailyCompletionStore, CompletionCounterStore, ReminderSkip, SortOption, etc).
- Implication for real-device watch installs: the watch app's signing must line up with
  the companion bundle id `app.alanvardy.SingleThread` and the `group.app.alanvardy.
  SingleThread` app-group entitlement.

## Q4: `xcrun devicectl` on this machine (live probe, 2026-09-17)

- `xcrun devicectl list devices -j` requires a path arg (`-j -` → JSON to stdout; human
  table to stderr). Top-level `payload["result"]["devices"]`. Every entry carries a
  `_deprecationNotice` that `hardwareProperties`/`deviceProperties`/`connectionProperties`
  are deprecated in favor of the `properties` dictionary.
- **A real Apple Watch Ultra IS paired** and developer-mode enabled:
  `platform:"watchOS"`, `deviceType:"appleWatch"`, `productType:"Watch6,18"`,
  `marketingName:"Apple Watch Ultra"`, `reality:"physical"`, watchOS 26.6 (build 23U67),
  `bootState:"booted"`, `developerModeStatus:"enabled"`.
  `identifier` (CoreDevice pairing UUID) = `6EF5C1CD-A890-559B-98D5-8F7F5A5A699A`;
  `hardwareProperties.udid` = `00008301-209B793C010BC02E`. `connectionProperties`:
  `transportType:"localNetwork"`, `pairingState:"paired"`,
  `tunnelState:"disconnected"`, `authenticationType:"manualPairing"`.
  **However `properties.connection.state = "disconnected"`** — paired but not currently
  reachable over the network tunnel. Human-table State column: `available (paired)`.
  (Contrast: the iPad is `wired`/`tunnelState:connected`/`connection.state:"connected"`;
  the iPhone is also paired but `disconnected`.)
- **Reachability** has no `reachability` field; it is derived from
  `properties.connection.state` + `pairingState` + `connectionProperties.tunnelState`
  (+ the human-table State column). Note the watch's state is `"disconnected"`, not
  `"unavailable"`, so the existing run-devices.sh unreachable predicates (`:80-82`)
  would NOT classify the watch as unreachable — but the platform/deviceType filter
  (`:66,68`) excludes it anyway today.
- **`device install app`**: `devicectl device install app --device <uuid|ecid|serial|
  udid|name|dns_name> <path>`; `--device` accepts UUID/ECID/serial/UDID/name/DNS; takes
  the `.app` bundle path. No platform-specific flags.
- **`device process launch`**: `devicectl device process launch [opts] --device <…>
  <bundle-id-or-path> [args]`; options `-u/--user`, `-e/--environment-variables`
  (JSON), `--start-stopped`, `--working-directory`, `--arch`, `--payload-url`,
  `--activate/--no-activate` (default activate), `--terminate-existing`, `--display`,
  `--launch-persistent-identifier` (from install's launchServicesIdentifier), `--console`.
  Flags declared "not supported on all platforms": `--activate/--no-activate`,
  `--terminate-existing`, `--display`. Repo currently uses `--terminate-existing
  --activate` (`run-devices.sh:143`) for iOS.
- WatchOS sims also appear in the same list (`reality:"simulated"`, `transportType
  "sameMachine"`, no developerModeStatus): Apple Watch Series 11 (46mm)×2, CI Watch
  S11-local, LocalTest Watch, Probe Watch S9 (26.0).

## Q5: How Makefile / CI build & test the watch today

**File: `Makefile` / `.github/workflows/ci.yml`**

- `Makefile:8` `WATCH_SIM := generic/platform=watchOS Simulator` (build-only).
  `Makefile:12-21` `WATCH_TEST_SIM` resolves a concrete UDID from
  `xcrun simctl list devices available`, awk-matching "Apple Watch Series 11 (46mm)",
  then `platform=watchOS Simulator,id=<UDID>` (`Makefile:14-15`); `?=` override.
- `watch-build` (`Makefile:40-41`): `xcodebuild -scheme SingleThreadWatch -destination
  '$(WATCH_SIM)' -configuration Debug -derivedDataPath DerivedData build`.
- `watch-test` / `watch-ui-test` (`Makefile:107-120`): same but concrete `WATCH_TEST_SIM`
  destination, `test -only-testing:SingleThreadWatchTests` / `…UITests`.
- CI `lint` job `Watch build` step (`ci.yml:234-241`): `xcodebuild -scheme
  SingleThreadWatch -destination "generic/platform=watchOS Simulator" -configuration
  Debug build` — **no `-derivedDataPath`, no signing flags**.
- CI `watch-ui-tests` job (`ci.yml:247-317`): pins a standalone created watch sim
  (`ci.yml:270-280`, `simctl create` + exports `WATCH_UDID`), boots it (`:282-285`),
  `build-for-testing` with concrete `platform=watchOS Simulator,id=$WATCH_UDID` +
  `-derivedDataPath` (`:287-297`), then UI smoke (`:299-308`) and unit tests (`:310-317`).
- **No code anywhere builds for a real watch device** (`Debug-watchos`); test plumbing
  only documents the sim product path `DerivedData/Build/Products/Debug-watchsimulator/…`
  (`scripts/test.sh:315-317`). `CODE_SIGNING_ALLOWED=NO` appears only on macOS jobs
  (`ci.yml:177,187`; `Makefile:44`); watch legs pass no signing flags and rely on
  Automatic signing for the simulator.

## Cross-Cutting Observations

- **Whole script is a single bash flow** — discovery → build → per-device
  install/launch → (mac leg) → summary; adding a watch leg means threading a second
  product build (watch) and a watch install/launch into the same script, reusing the
  existing devicectl install/launch surface.
- **Two distinct devicectl surfaces are already proven in-repo**: `list devices -j`
  (with a python filter) and `device install app` / `device process launch`. The watch
  uses the exact same subcommands; only discovery filtering (platform/deviceType) differs.
- **Signing posture differs by platform in this repo**: iOS installs use Automatic
  signing (no flags), macOS forces `CODE_SIGNING_ALLOWED=NO` (unsigned). A real-device
  watch install is unlike the macOS case — it must be signed (device install requires a
  signed bundle) and watched with the app-group entitlement.
- **`--device` is polymorphic** — UUID/ECID/serial/UDID/name/DNS — so either the watch's
  CoreDevice `identifier` or its `udid` can target install/launch.
- **Reachability idiom** in the repo keys off transportType/connection.state/tunnelState;
  a real but momentarily-unreachable watch shows `connection.state:"disconnected"`, not
  `"unavailable"`.

## Open Areas

- **Watch install target model** — whether `devicectl device install app --device
  <watch-udid>` installs directly to the watch, or whether a real watch must first be
  made reachable (tunnel up via the paired iPhone) before install is possible. Not
  provable today: the watch is paired but `connection.state:"disconnected"`. This is the
  single highest-uncertainty item and should be validated with the watch reachable
  (ideally the iPhone connected) before committing the approach.
- **Real-device watch build product path** — `generic/platform=watchOS` + Automatic
  signing should produce `DerivedData/Build/Products/Debug-watchos/SingleThreadWatch
  .app`, but this exact path is unverified (no real-device watch build exists anywhere).
- **Signing/provisioning for a real watch** — whether the existing Automatic-signed
  Debug build for the watch bundle id (`…watchkitapp`) with the companion + app-group
  entitlement installs as-is, or needs provisioning/signing adjustments, is unproven.
  `Debug-watchos` product is never produced or verified by any test today.
- **Companion requirement** — whether the phone app must be installed first (or is
  installed implicitly) for the watch app to run; the watch declares
  `WKCompanionAppBundleIdentifier` but nothing in the repo installs the pair together.
