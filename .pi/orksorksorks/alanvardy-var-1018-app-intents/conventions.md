# Project Conventions (SingleThread)

Shared factual appendix for Design/Structure/Plan. All `file:line` references are
to the repo root (`/Users/vardy/dev/alanvardy-var-1018-app-intents`).

## Canonical commands

| Action | Command | Where |
|---|---|---|
| Build iOS app (Debug, for testing) | `make build` (or `SIM=<dest> make build`) | `Makefile:26` |
| Watch build | `make watch-build` | `Makefile:29` |
| macOS build / test (native unit tests) | `make mac-build` / `make mac-test` | `Makefile:32,35` |
| Full CI-identical gate | `./scripts/test.sh` (or `make check`) | `scripts/test.sh`, `Makefile:112` |
| Unit tests only | `make test` → `./scripts/test.sh --unit-only` (macOS native, `-only-testing:SingleThreadTests`) | `Makefile:87`, `scripts/test.sh:314-334` |
| UI tests only | `make ui-test` → `./scripts/test.sh --ui-only` (iOS sim) | `Makefile:90`, `scripts/test.sh:343-354` |
| Watch UI tests | `make watch-ui-test` (`-only-testing:SingleThreadWatchUITests`) | `Makefile:96` |
| Watch unit tests | `make watch-test` (`-only-testing:SingleThreadWatchTests`) | `Makefile:104` |
| Simulator verify | `make simverify` | `Makefile:93` |
| Clean | `make clean` | `Makefile:115` |
| Lint (format-check + swiftlint --strict) | `make lint` | `Makefile:118-120` |
| Format (apply) | `make format` | `Makefile:122-124` |
| Periphery (strict) | `make periphery` | `Makefile:126` |
| Single test case | `scripts/test-one.sh <Target/Suite/case>` (exit ≠ 0 on zero matches) | `scripts/test-one.sh` |

- **Gate staging**: full `./scripts/test.sh` runs **once** at the end via the
  `run-gate` skill (async gate subagent, managed worktree, multi-hour timeout) —
  never ad-hoc `nohup`. Phase subagents verify with build + targeted
  `-only-testing:` suites only.
- Full gate contents (`scripts/test.sh:245-333`): iOS build-for-testing → watch
  build → Periphery (skip-build, `DerivedData/Index.noindex/DataStore`) → iOS UI
  tests → watch UI tests + watch unit tests (build+test) → macOS unit tests.
- CI: `.github/workflows/ci.yml` matrix runs **both** `iPhone 17` and `iPad (A16)`
  iOS simulators in parallel jobs (see AGENTS.md).

## Destination pinning

- Precedence: explicit `SIM=` > worktree `.simulator_id` > shared default
  `platform=iOS Simulator,name=iPhone 17` (`Makefile:6-10`).
- A bare `name=iPhone 17` hangs when multiple runtimes exist; `scripts/test.sh`
  resolves name-only destinations to a concrete UDID via `resolve_sim_udid()`
  (`scripts/test.sh:23-31`); an unanchored match can select the leftover
  **`Gate iPhone 17`** sim.
- Watch UI tests need a **concrete** watch sim: `WATCH_TEST_SIM='platform=watchOS
  Simulator,id=<26.5-UDID>'` for an unpaired watch (`Makefile:14-16`,
  `scripts/test.sh:9-12`).

## Concurrency / language-mode facts

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_VERSION = 6.0` on the iOS
  app and watch app targets only (`project.pbxproj:777,827,961,989`);
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` (AGENTS.md:50). **Not** on
  SingleThreadCore, widget, or test targets — code there must annotate
  `@MainActor` explicitly (AGENTS.md:44-50).
- iOS deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
  (`project.pbxproj:765,815,843,872,900,924,1009,1040`). Local Xcode 27.0 vs CI
  26.6: 27 misses `$`-projection-only `@State` (CI-green) — Periphery divergence,
  see the `periphery` skill before changing the deployment floor.
- `DEBUG_INFORMATION_FORMAT = dwarf` (Debug builds only); release switches to
  `dwarf-with-dsym`. `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide —
  per-target overrides go in the pbxproj, never CLI flags.
- One xcodebuild test process at a time; on `Busy`/`RequestDenied` shut down sims
  and kill orphaned `xcodebuild`/`xctest` (see `simulator-pairing` skill).

## Test-suite inventory

| Suite | Location | Framework | Platform / gating |
|---|---|---|---|
| SingleThreadTests | `SingleThreadTests/` (82 `.swift` files) | Swift Testing (`import Testing`, `@Test`) | Runs natively on **macOS** (`-only-testing:SingleThreadTests`) |
| SingleThreadUITests | `SingleThreadUITests/SingleThreadUITests.swift` | XCTest + a11y audit (`testAccessibilityAudit`) | Runs on **iOS simulator** (`-only-testing:SingleThreadUITests`) |
| SingleThreadWatchTests | `SingleThreadWatchTests/` | Swift Testing | **watchOS** simulator (`-only-testing:SingleThreadWatchTests`) |
| SingleThreadWatchUITests | `SingleThreadWatchUITests/` | XCTest (un-renamed `test…` names) | **watchOS** simulator; needs concrete `WATCH_TEST_SIM` |

- **Naming rules**: unit-test (Swift Testing) method names must NOT start with
  `test`/`testing` — SwiftFormat strips those prefixes (phantom diffs under
  `make format`). UI-test (XCTest) names keep `test…` (excluded from SwiftFormat
  via `--exclude SingleThreadUITests`; `SingleThreadWatchUITests` is NOT excluded
  but keeps `test…` names — it is XCTest).
- **Identifier rule**: variable names ≥ 3 chars (`identifier_name`; exceptions
  `id, e, d, rt, to, gvm`). Force-unwrapping banned outside tests (relaxed in
  `SingleThreadTests/.swiftlint.yml`).
- Intent-related coverage today: `SingleThreadTests/ReminderIntentsTests.swift`
  (config/title checks only), `ReminderStoreTests.swift` (visible/priority/empty
  `:20-114`, skip `:268-372`, complete `:397-439`), `ListContentTests.swift:9-47`.
- Deterministic iOS UI test seam: `--seed '<json>'` launch arg backed by
  `InMemoryEventStore` + `--ui-testing` / `--ui-testing-noop-settle` seams
  (`AppViewModel.swift:252,260,297,332-351,360-380`; `UITestingSeed.swift`).
  Every persisted value shared with the watch must round-trip through
  `AppGroup.defaults` (`UserDefaults(suiteName:)`), never `UserDefaults.standard`.

## Lint / format specifics

- SwiftFormat (`.swiftformat`) enables `organizeDeclarations`,
  `blankLinesAroundMark`, `preferSwiftTesting`; disables `trailingCommas`,
  `trailingClosures`, `isEmpty`. iOS UI tests excluded (repo AGENTS.md).
- SwiftLint runs `--strict` in CI (`make lint`), every warning is an error;
  config auto-discovered from repo root (`.swiftlint.yml`).

## Known build/test gotchas

- `make periphery` reads a stale build index after branch switches — clean
  `DerivedData/` and rerun first (repo AGENTS.md; `periphery` skill).
- Three macOS `EntitlementStoreTests` fail locally but are green on CI
  (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`,
  `hostStoreKitIsClean` canary) — pre-existing, do not debug; annotate.
- Watch UI runner on this machine needs `lib_TestingInterop.dylib` embedded into
  the runner Frameworks — `scripts/test.sh:280-292` handles it locally; harmless
  on CI.
- Remote/local CI uses Xcode 26.6; local 27.0 misses `$`-projection-only `@State`
  (CI-green) — Periphery findings can disagree; split
  `verify_deployment_target()` before any floor change.
- All changes go through PRs merged with `gh pr merge <n> --rebase --delete-branch`;
  never push to main directly (repo-local AGENTS.md).