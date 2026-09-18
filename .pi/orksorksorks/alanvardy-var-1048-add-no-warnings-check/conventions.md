# Conventions — Shared Factual Appendix

Dense reference for Design, Structure, and Plan. Cites `file:line` so later
phases don't re-read the sources.

## Canonical commands (from Makefile / scripts / CI)

| Command | Effect | Source ref |
|---|---|---|
| `make check` | Full gate `./scripts/test.sh` (format → lint → build → periphery → UI → watch → mac unit) | `Makefile:123-124` |
| `make test` | `./scripts/test.sh --unit-only` (macOS native unit tests) | `Makefile:98-99` |
| `make ui-test` | `./scripts/test.sh --ui-only` (iOS UI tests) | `Makefile:101-102` |
| `make build` | iOS `xcodebuild -scheme SingleThread … build-for-testing` | `Makefile:37` |
| `make watch-build` | Watch `xcodebuild -scheme SingleThreadWatch … build` | `Makefile:40` |
| `make mac-test` / `mac-build` | macOS variant (`CODE_SIGNING_ALLOWED=NO`) | `Makefile:43,46` |
| `make lint` | `swiftformat --lint <7 dirs>` + `swiftlint lint --strict` | `Makefile:129-131` |
| `make format` | `swiftformat <7 dirs>` + `swiftlint --fix` | `Makefile:133-135` |
| `make periphery` | `periphery scan --strict -- -destination "$(SIM)"` | `Makefile:137-138` |
| **Single test** | `scripts/test-one.sh <Target/Suite/case>` (bounds run, zero-match → non-zero) | `scripts/test-one.sh` |

- Gate entry: `set -euo pipefail` (`scripts/test.sh:2`); success `echo "✅ All CI checks passed."; exit 0` (`test.sh:348-349`).
- **`make check` does not run in CI.** CI re-implements phases as separate steps (see CI inventory below). A change to `scripts/test.sh` is exercised locally (and via `make check`), not by CI's step path, unless CI is also touched.

## Test-suite inventory

| Target / dir | Framework | Run command (test.sh line) | Run in CI |
|---|---|---|---|
| `SingleThreadTests/` (~82 Swift Testing files) | Swift Testing (`import Testing`, `@Test`) | macOS-native `test -only-testing:SingleThreadTests` with `CODE_SIGNING_ALLOWED=NO`, full mode `test.sh:340-347`, unit-only `test.sh:355-360`; single `scripts/test-one.sh` | `unit-tests` builds **on iOS sims** `ci.yml:52-58`, tests `ci.yml:67-75`; `mac-tests` macOS `ci.yml:173-190` |
| `SingleThreadUITests/SingleThreadUITests.swift` | XCTest (`test…`) | iOS `test-without-building -only-testing:SingleThreadUITests`, full `test.sh:294-298`, UI-only `test.sh:378-382` | `ui-tests-smoke` `ci.yml:121-141` |
| `SingleThreadWatchTests/` (6 files) | Swift Testing | watch `test-without-building -only-testing:SingleThreadWatchTests` `test.sh:332-336` | `watch-ui-tests` `ci.yml:313` |
| `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` | XCTest (`test…`) | watch `test-without-building -only-testing:SingleThreadWatchUITests` `test.sh:324-329` | `watch-ui-tests` `ci.yml:302` |

- **Naming rule**: unit-test names must not start with `test`/`testing` (SwiftFormat strips+renames them); UI/XCTest names keep `test…`. Force-unwrapping banned outside test code; relaxed in `SingleThreadTests/.swiftlint.yml`.
- Watch bundle build-for-testing (both bundles at once) is at `test.sh:302-307`.

## Build / verify gotchas surfaced

- **Warnings-as-errors default**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-level (`pbxproj:676,731`); only `SingleThreadTests` overrides to `NO` (`pbxproj:856,885`) with a documented StoreKitTest rationale (`pbxproj:858-860,887-889`). **Do not toggle warnings-as-errors via CLI flags in xcodebuild** — conflicts with the SPM package's `-suppress-warnings` (`AGENTS.md:145-147`); scope per-target via pbxproj.
- **`Package.swift`** (`SingleThreadCore/Package.swift:1-18`) currently has **no** `-suppress-warnings` / `-Wno` — the AGENTS.md caution is conceptual, not present config.
- **No build-log capture in `scripts/test.sh`** — every xcodebuild streams live (`test.sh:252,282,294,302,324,332,340,355,369,378`). The only in-repo capture idiom: `scripts/test-one.sh:30-58` (`> "$LOG" 2>&1 &`, `tail -25` on failure, zero-match detection via `xcresulttool get test-results summary`).
- **Destination pinning**: name-only `iPhone 17` is ambiguous with multiple runtimes; use explicit `SIM=` > `.simulator_id` > default. Watch UI tests need an **unpaired** watch pinned by UDID (`WATCH_TEST_SIM='platform=watchOS Simulator,id=<udid>'`). Watch build/test destination normalization trap documented at `test.sh:258-275`.
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied`, shut down sims and kill orphaned `xcodebuild`/`xctest`.
- **SwiftLint `--strict`** in all three callers (`Makefile:131`, `test.sh:248`, `ci.yml:232`).
- Known local-only macOS `EntitlementStoreTests` failures (do not debug): `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` (CI mac-tests green).
- Periphery reads a stale build index after branch switches — clean `DerivedData/` and rerun.

## CI inventory (`.github/workflows/ci.yml`, 337 lines)

- All jobs `runs-on: macos-26`, Xcode pinned `26.6` via `maxim-lobanov/setup-xcode` (`ci.yml:27,96,154,205,255`). Jobs gated by `if: github.event_name != 'pull_request' || …dependabot[bot]'`.
- `unit-tests` (iOS matrix iPhone 17/iPad, job `ci.yml:15`): build `-only-testing:SingleThreadTests` `ci.yml:52-58`; test `-parallel-testing-enabled NO …` + `-resultBundlePath TestResults.xcresult` `ci.yml:67-75`; upload results only `if: failure()` `ci.yml:78`.
- `ui-tests-smoke` (job `ci.yml:84`, build `ci.yml:121-127`, test `ci.yml:136-141`); `mac-tests` (job `ci.yml:146`, build `ci.yml:173-179`, test + `TestResults-mac.xcresult` `ci.yml:184-190`, upload `if: failure()` `ci.yml:193`); `lint` (job `ci.yml:199`; swiftformat `ci.yml:228`, `swiftlint lint --strict` `ci.yml:232`, watch build `ci.yml:237-241`, periphery `ci.yml:245`); `watch-ui-tests` (job `ci.yml:247`, watch build `ci.yml:290-297`, watch UI bundle `ci.yml:302`, watch unit bundle `ci.yml:313`); `secret-scan` (gitleaks) `ci.yml:319`.
- CI build output streams to step logs only; **no build-log artifact uploaded**.