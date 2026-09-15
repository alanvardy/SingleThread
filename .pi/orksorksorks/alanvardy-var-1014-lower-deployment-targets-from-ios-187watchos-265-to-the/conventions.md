# Conventions — Shared Factual Appendix

Reference for Design/Structure/Plan. All paths relative to the repo root
(`/Users/vardy/dev/SingleThread`, worktree
`/Users/vardy/dev/alanvardy-var-1014-lower-deployment-targets-from-ios-187watchos-265-to-the`).

## Canonical Commands

| Purpose | Command | Source |
|---|---|---|
| Build | `make build` | `Makefile` (`make help` lists all) |
| Unit tests | `make test` | `Makefile` → `scripts/test.sh` (unit mode) |
| UI tests | `make ui-test` | `Makefile` |
| Watch tests | `make watch-test` / `make watch-ui-test` | `Makefile` |
| macOS tests | `make mac-test` | `Makefile` |
| Full CI-identical gate | `./scripts/test.sh` (formats, lints, builds, Periphery, unit + UI tests) | `repo-facts`; run via the `run-gate` skill (async gate subagent, managed worktree), never ad-hoc `nohup` |
| Single test | `scripts/test-one.sh <Target/Suite/case>` (exits non-zero on zero matches) | `scripts/test-one.sh`; repo `AGENTS.md` |
| Targeted suites | `xcodebuild -only-testing:SingleThreadTests` (Swift Testing) / `-only-testing:SingleThreadUITests` (XCTest) | repo `AGENTS.md` |
| Periphery | `make periphery` (full scan `periphery scan --strict -- -destination "$(SIM)"`, `Makefile:158`); gate form `periphery scan --skip-build --index-store-path DerivedData/Index.noindex/DataStore --strict` (`scripts/test.sh:240-241`, CI lint `ci.yml:260`) | `Makefile`, `scripts/test.sh` |
| Lint | `swiftlint lint --strict` (CI runs `--strict`; config `.swiftlint.yml` auto-discovered) | repo `AGENTS.md` |
| Format | `make format` (SwiftFormat; iOS UI tests excluded via `--exclude SingleThreadUITests`) | repo `AGENTS.md` |
| Simulator pinning | `SIM=... make test` (precedence: explicit `SIM=` > `.simulator_id` > default `name=iPhone 17`) | `Makefile:1-11`; `scripts/test.sh:56-70` |
| Clean | `make clean` (also: clean `DerivedData/` before `make periphery` after branch/setting changes) | `Makefile`; `AGENTS.md:28` |

## Test-Suite Inventory

| Suite / path | Kind | Covers | Gating / notes |
|---|---|---|---|
| `SingleThreadTests/` | Swift Testing (`import Testing`, `@Test`) | Unit: stores (ReminderStore, EventKitStoring fakes `ReminderStoreTests.swift:1038,1046`, `EventKitStoringTests.swift:13,29,56,65`), entitlement (EntitlementStoreTests), app delegate (`AppDelegateTests.swift:13` — notes newer-deployment-target-only API), etc. | iOS+macOS test target (`IPHONEOS`/`MACOSX` deployment targets, pbxproj:843-844/872-873). Test names must NOT start with `test`/`testing` (SwiftFormat strips prefixes); fixtures relax force-unwrap via `SingleThreadTests/.swiftlint.yml`. Known local-only failures (pre-existing, don't debug): `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` |
| `SingleThreadUITests/` | XCTest | iOS UI + accessibility audit (`testAccessibilityAudit` / `performAccessibilityAudit`) | iOS target (pbxproj:900-901/924-925). SwiftFormat-excluded; keep `test…` names. Driven deterministically via `--seed '<json>'` (InMemoryEventStore) for write flows |
| `SingleThreadWatchTests/` | Swift Testing | Watch unit | watchOS target (pbxproj:1123/1147). SwiftFormat applied (not excluded) — keep non-`test` names |
| `SingleThreadWatchUITests/` | XCTest | Watch UI + accessibility | watchOS target (pbxproj:1077/1099); needs paired iPhone+watch sims; `--ui-testing` seam (WatchAppViewModel.swift:156,165) |
| macOS tests | Swift Testing | macOS app tests | CI `mac-tests` runs `platform=macOS` (`ci.yml:172`); `make mac-test` |
| CI matrix | — | unit-tests `["iPhone 17","iPad (A16)"]` (`ci.yml:8-10`), ui-tests-smoke `["iPhone 17"]` (`:65-67`) | Simulators addressed by device name; runtimes are whatever is installed (latest). iOS `iPhone 17` is the local default sim; `iPad (A16)` also supported |

Swift Testing suites are gated via `-only-testing:` entries in `scripts/test.sh`
and the `Makefile` `test` target; new suites must be added to both
(repo `AGENTS.md`).

## Build / Verify Gotchas

- **Deployment-target consistency gate**: `scripts/test.sh:130-192` `verify_deployment_target()` (invoked `:193` before every build) asserts all **20** pbxproj literals (8 iOS / 6 macOS / 6 watchOS) + **3** Package.swift literals match; defaults `DEPLOYMENT_TARGET_IOS=18.7`, `DEPLOYMENT_TARGET_OTHER=26.5`, **env-overridable** (`:138-139`); count-drift checks `EXPECTED_TARGET_LITERALS=20`, `EXPECTED_PACKAGE_LITERALS=3` (`:140-141`); drift → exit 1. Comment `:131-137`: 18.7 is not a valid watchOS/macOS floor under Xcode 26.
- **Current floors (single source per target)**: `SingleThreadCore/Package.swift:7-9` — `.iOS("18.7")`, `.watchOS("26.5")`, `.macOS("26.5")`; pbxproj literals at 765-1147 (line map in `research.md` Q1).
- **Hard floor (SDK-annotated)**: EventKit `requestFullAccessToRemindersWithCompletion` is `API_AVAILABLE(ios(17.0), macos(14.0), watchos(10.0))` (`iPhoneOS.sdk/.../Headers/EKEventStore.h:88`). `@Observable` (Swift 6.0 stdlib) floor is toolchain-wide, unannotated locally.
- **Simulator pairing**: watch UI tests need paired iPhone+watch sims (`simulator-pairing` skill); name-only `iPhone 17` dest is ambiguous when multiple runtimes exist — bare `name=` can hang; `resolve_sim_udid()` (`scripts/test.sh:36-42`) pins to the worktree `.simulator_id` (currently `BFB5C8FB-5ED5-48AD-9149-298E20FCB4E6`); can select the leftover `Gate iPhone 17` sim if unanchored.
- **One xcodebuild test process at a time**; on `Busy`/`RequestDenied` shut down sims and kill orphaned `xcodebuild`/`xctest` (AGENTS.md:32-34).
- **Stale DerivedData/Periphery**: `make periphery` reads a stale build index after branch switches — clean `DerivedData/` and rerun (AGENTS.md:28). CI caches `DerivedData` keyed on `hashFiles(...project.pbxproj)` (`ci.yml:33-45` etc.) — a pbxproj edit busts the cache automatically.
- **Debug builds only**: `DEBUG_INFORMATION_FORMAT = dwarf`; release switches to `dwarf-with-dsym`.
- **Warnings as errors**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; exceptions: Tests Debug:856/Release:885 set `NO` for a StoreKit iOS-18-deprecated symbol (pbxproj:853/882 comments). `CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE` (pbxproj:647/710) — unguarded calls to newer APIs warn (aggressive = warning); lowering floors widens what compiles.
- **Watch sim runtime quirk**: local watchOS 26.5 simruntime lacks `lib_TestingInterop.dylib`; workaround bundles the Xcode lib into the watch UI test runner (`scripts/test.sh:271-288`; `simulator-pairing` SKILL.md:24).
- **UI-test parallel clones disabled** in CI (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`, ci.yml:88-91,153-155) due to EventKit/EKReminder SIGTRAP flakiness.
- **Gate staging**: phase subagents verify with build + targeted `-only-testing:` suites; full `./scripts/test.sh` runs once after phases commit via `run-gate` skill (async gate subagent, managed worktree, multi-hour timeout). Two consecutive UI-stage contention failures → stop re-running locally; CI is authoritative.
- **Env/lint strictness**: `identifier_name` ≥ 3 chars (exceptions `id`, `e`, `d`, `rt`, `to`, `gvm`); force-unwrapping banned outside tests; `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch app targets (widget/core targets need explicit `@MainActor`); Swift 6 language mode.
- **Distribution surface**: no in-repo store/README/CHANGELOG OS-requirement text exists; only `docs/` (SimulatorManualVerification.md, TestFlight-macOS.md), `exportOptions.plist` (app-store-connect, teamID `6NWX2DHB9Q`), and `AGENTS.md`/`.pi/` internal artifacts state anything about floors.