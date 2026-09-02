# Q5 — What the local and CI macOS pipelines actually run (and what is not exercised)

All references are to files under `/Users/vardy/dev/alanvardy-var-721-testflight-macos`.

## 1. Destination constants shared by local + CI

- `Makefile:8` — `MAC_SIM := platform=macOS`
- `Makefile:1` — `SIM ?= platform=iOS Simulator,name=iPhone 17` (iOS, not macOS)
- `Makefile:2` — `WATCH_SIM := generic/platform=watchOS Simulator`
- `scripts/test.sh:12` — `MAC_SIM="platform=macOS"` (mirrors Makefile)
- `scripts/simverify.sh:8` — `MAC_SIM="platform=macOS"` (declared but **never used**; the script only touches the iOS sim)
- `.github/workflows/ci.yml:297,308` — mac-tests job uses the literal `-destination "platform=macOS"`

## 2. Makefile macOS targets

- `mac-build` (`Makefile:23-24`):
  `xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO build`
  → **build only**, Debug, `CODE_SIGNING_ALLOWED=NO`. No `-only-testing`, no tests, no signing.
- `mac-test` (`Makefile:26-27`):
  `xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests`
  → combined **build+test**, `CODE_SIGNING_ALLOWED=NO`, **only the `SingleThreadTests` bundle** is run on macOS. No `-configuration` (scheme TestAction is Debug — `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme`, TestAction attribute `buildConfiguration`). `SingleThreadUITests` is excluded.
- `mac-build`/`mac-test` are listed in `.PHONY` (`Makefile:15`). They do **not** invoke `scripts/test.sh`, so they do **not** run the deployment-target guard (see §5).
- `Makefile:71-72` — `check:` runs `./scripts/test.sh` (full pipeline), which does contain a macOS step (see §3).
- No Makefile target performs macOS archiving, macOS Release builds, macOS UI tests, or shows build settings.

## 3. scripts/test.sh macOS steps

- Deployment-target guard `verify_deployment_target` (`scripts/test.sh:119-186`) is invoked unconditionally at `scripts/test.sh:188` in **all three modes** (full, `--unit-only`, `--ui-only`), before any build. It is a static literal checker: every `(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET` in `SingleThread.xcodeproj/project.pbxproj` must equal the per-platform floor (iOS `18.7`, other `26.5`, env-overridable `DEPLOYMENT_TARGET_IOS`/`DEPLOYMENT_TARGET_OTHER`, `scripts/test.sh:114-115`), and every `.iOS/.watchOS/.macOS` literal in `SingleThreadCore/Package.swift` must match (`scripts/test.sh:152-172`). Drift → `exit 1` (`scripts/test.sh:176-179`). Notes:
  - Covers the macOS floor: current pbxproj has 6 `MACOSX_DEPLOYMENT_TARGET = 26.5` literals (`SingleThread.xcodeproj/project.pbxproj:765,815,841,870,898,922` — Debug+Release of app, unit tests, UI tests) and the package literal `.macOS("26.5")` (`SingleThreadCore/Package.swift:9`).
  - `EXPECTED_TARGET_LITERALS=16`/`EXPECTED_PACKAGE_LITERALS=3` (`scripts/test.sh:116-117`) are defined but **never referenced** by the verification logic; the guard compares values per literal only (it does not check the literal *count*; the file currently has 20 deployment-target literals: IPHONEOS×8, MACOSX×6, WATCHOS×6 at `project.pbxproj:762-1144`).
- Full mode (`./scripts/test.sh`, ≡ `make check`) macOS step (`scripts/test.sh:267-277`): **macOS build only**:
  `xcodebuild -scheme $SCHEME -destination $MAC_SIM -configuration Debug -derivedDataPath $DERIVED_DATA CODE_SIGNING_ALLOWED=NO build`
  — no `test`, no `-only-testing`. It is the last step before `✅ All CI checks passed.` (`scripts/test.sh:278-279`).
- **No macOS unit or UI tests run inside scripts/test.sh in any mode.** `--unit-only` (`scripts/test.sh:282-303`) and `--ui-only` (`scripts/test.sh:306-317`) contain only iOS-simulator `build-for-testing` + `test-without-building` steps; no macOS step at all. macOS unit-testing exists only in `make mac-test` and the CI `mac-tests` job.
- All other pipeline steps target the iOS sim (`scripts/test.sh:216-226`, `231-236`) and watch (`scripts/test.sh:239-264`).

## 4. scripts/simverify.sh and scripts/run-devices.sh — no macOS involvement

- `scripts/simverify.sh` (entire file): iOS Simulator only — boots the `name=iPhone 17` sim (`simverify.sh:17-23`), `build-for-testing -only-testing:SingleThreadUITests` (`simverify.sh:27-33`) then `test-without-building -only-testing:SingleThreadUITests` (`simverify.sh:35-39`) against `SIM` (`simverify.sh:6`), plus a best-effort screenshot (`simverify.sh:42-43`). `MAC_SIM` is declared (`simverify.sh:8`) but never referenced. No macOS.
- `scripts/run-devices.sh`: physical **iOS** devices only — discovers paired iPhone/iPad with Developer Mode enabled via `xcrun devicectl list devices` (`run-devices.sh:44-66`), builds once with `-destination 'generic/platform=iOS'` (`run-devices.sh:73-77`), then `devicectl device install app` / `device process launch` per device (`run-devices.sh:88-99`). No macOS, no tests.

## 5. CI (.github/workflows/ci.yml) — the mac-tests job

- Only workflow file: `.github/workflows/ci.yml`. Jobs: `unit-tests`, `ui-tests-flows`, `ui-tests-launch-appearance`, `ui-tests-audits`, **`mac-tests`** (`ci.yml:270`), `lint`, `watch-ui-tests`.
- `mac-tests` (`ci.yml:270-321`):
  - `runs-on: macos-26` (`ci.yml:271`); `setup-xcode` Xcode 26.6 (`ci.yml:276-279`); `env DEVELOPMENT_TEAM=` override to empty (`ci.yml:283`).
  - Dedicated DerivedData cache key prefix `derived-data-mac-…` with `hashFiles('SingleThread/**','SingleThreadTests/**','SingleThreadCore/**','SingleThreadWidget/**','SingleThread.xcodeproj/project.pbxproj')` — omits `SingleThreadWatch/**` and both watch test dirs (`ci.yml:285-291`).
  - **Build (macOS)** (`ci.yml:294-304`, timeout 20): `xcodebuild -scheme SingleThread -destination "platform=macOS" -configuration Debug -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build -showBuildTimingSummary` — plain `build`, Debug, codesigning off.
  - **Unit tests (macOS)** (`ci.yml:305-313`, timeout 20): `xcodebuild -scheme SingleThread -destination "platform=macOS" -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests -resultBundlePath TestResults-mac.xcresult` — combined `test` (re-builds), explicit `-only-testing:SingleThreadTests`, codesigning off, no `-configuration` (scheme Debug).
  - Artifact `mac-unit-test-results` (`TestResults-mac.xcresult`) uploaded on failure (`ci.yml:315-320`).
- The `lint` job (`ci.yml:322-378`) never touches macOS: swiftformat lint, swiftlint `--strict`, watch `build`, `periphery scan`. No deployment-target guard, no macOS build.
- **CI never runs `scripts/test.sh`** in any job (all steps are raw `xcodebuild`/tool invocations). Therefore the **deployment-target guard (`scripts/test.sh:188`) is never exercised in CI**, including the macOS floor (26.5) check.

## 6. Scheme/project facts relevant to the macOS runs

- `SingleThread.xcscheme` TestAction lists **both** `SingleThreadTests` and `SingleThreadUITests` as enabled testables (both `skipped="NO"`, `parallelizable="YES"`), yet no macOS invocation ever selects `SingleThreadUITests`.
- `SingleThread.xcscheme` BuildAction marks `SingleThread.app` and `SingleThreadWatch.app` with `buildForTesting="YES"` and `buildForArchiving="YES"`, so `xcodebuild test` on the scheme (as in `make mac-test`, CI mac-tests) builds both app buildables.
- Mac-capable targets: iOS-family targets declare `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`project.pbxproj:772,822,847,876,904,928,1016,1047`). `MACOSX_DEPLOYMENT_TARGET = 26.5` is set on the app/unit/UI-test configs only (`project.pbxproj:765,815,841,870,898,922`).
- Mac-specific app settings **never exercised** because every macOS build runs `CODE_SIGNING_ALLOWED=NO`: `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development"` (`project.pbxproj:740,790`), `ENABLE_APP_SANDBOX = YES` and `ENABLE_HARDENED_RUNTIME = YES` (`project.pbxproj:744-745,794-795`).
- `SingleThreadWidget` declares `macosx` in `SUPPORTED_PLATFORMS` (`project.pbxproj:1016,1047`) but has **no** `MACOSX_DEPLOYMENT_TARGET` (IPHONEOS-only at `project.pbxproj:1006,1037`); no build anywhere targets the widget at a macOS destination.

## 7. macOS-relevant verification NOT exercised anywhere

- **macOS UI tests: not exercised anywhere.** `SingleThreadUITests` is an enabled scheme testable (`.xcscheme` Testables), but `make mac-test` (`Makefile:26-27`), CI mac-tests (`ci.yml:305-313`), and every script restrict macOS runs to `-only-testing:SingleThreadTests`; `scripts/test.sh` full mode runs no macOS tests at all.
- **macOS unit tests in the local full pipeline: not exercised.** `make check`/`scripts/test.sh` does a macOS build only (`scripts/test.sh:267-277`); macOS unit tests run only via the separate `make mac-test` and the CI `mac-tests` job. `make ui-test`, `make simverify`, `make coverage*`, `make watch-*` are all iOS/watch.
- **macOS archiving / Release / distribution: not exercised anywhere.** No `archive`, no `-configuration Release` macOS build, no `exportOptionsPlist`/`-exportArchive` in the Makefile, any script, or `ci.yml` (grep for `archive|exportOptions|exportArchive` in `scripts/*.sh` and the workflow → 0 hits). No signed or notarized macOS product is ever produced or verified.
- **macOS signing/provisioning path: never exercised.** Every macOS build/test (Makefile:24,27; test.sh:267-277; ci.yml:294-304,305-313) forces `CODE_SIGNING_ALLOWED=NO`, so the configured macOS signing settings (Apple Development identity for `sdk=macosx*`, sandbox, hardened runtime — `project.pbxproj:740-745,790-795`) are compiled but never signed or launched.
- **Deployment-target validation on macOS: not exercised by the macOS-specific flows.** `mac-build`, `mac-test`, and the CI `mac-tests` job run no deployment-target checks; the guard exists only inside `scripts/test.sh` (`scripts/test.sh:119-188`) and CI never invokes that script. A `MACOSX_DEPLOYMENT_TARGET` drift would pass `make mac-test` and the CI `mac-tests` job and be caught only by `make check`/`make test`/`make ui-test` locally.
- **macOS app launch/behavior on any device: not exercised anywhere.** `run-devices.sh` installs/launches only on iOS physical devices; `simverify.sh` gates only iOS-simulator appearance; no step runs or launches the built macOS app bundle.
- **Widget macOS build: never exercised.** No destination (Makefile, scripts, CI) builds `SingleThreadWidget` for `platform=macOS`, so the widget's `macosx`-in-`SUPPORTED_PLATFORMS`-without-`MACOSX_DEPLOYMENT_TARGET` state (`project.pbxproj:1006,1016,1037,1047`) is never surfaced by a macOS build.
