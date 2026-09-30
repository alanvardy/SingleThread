# Conventions

## Canonical Commands

- **Gate**: `./scripts/test.sh` (full CI-identical; or `make check`). Run once via the `run-gate` skill in a managed worktree — never `nohup`. Staging subagents verify with targeted `-only-testing:` suites, not the full gate.
- **Build**: `make build` (iOS simulator), `make watch-build`, `make mac-build`.
- **Unit tests (iOS)**: `make test` → `./scripts/test.sh --unit-only`; targeted: `xcodebuild -only-testing:SingleThreadTests`.
- **UI tests**: `make ui-test` → `./scripts/test.sh --ui-only`.
- **macOS tests**: `make mac-test`.
- **Watch tests**: `make watch-test` / `make watch-ui-test`.
- **Format**: `make format` (swiftformat `SingleThread/ SingleThreadTests/ SingleThreadUITests/`; iOS UI tests excluded via `--exclude SingleThreadUITests`).
- **Lint**: `make lint` (swiftformat `--lint` + `swiftlint lint --strict`).
- **Periphery**: `make periphery` (`periphery scan --strict`). Clean `DerivedData/` and rerun after branch switches (stale build index). A new SPM dependency can add SDK-side Periphery noise — consult the `periphery` skill before "fixing" findings.
- **Single test**: `scripts/test-one.sh <Target/Suite/case>` — exits non-zero on zero matched cases.
- **Sim destination**: `SIM=` explicit > `.simulator_id` worktree file > default `iPhone 17`. Pin with `SIM=`. One xcodebuild test process at a time; on `Busy`/`RequestDenied` shut down sims and clear orphans (see `simulator-pairing` skill).

## Test-Suite Inventory

All unit tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Names must NOT start with `test`/`testing` (SwiftFormat strips them). UI/XCTest names keep `test…`. Force-unwrapping banned outside test code (relaxed for fixtures via `SingleThreadTests/.swiftlint.yml`).

### SingleThreadTests (iOS/macOS unit tests) — SingleThreadTests/
Flat `<Subject>Tests.swift` files (~80), single `struct <Name>Tests`, imports `Foundation`/`SingleThreadCore`/`Testing`, app code via `@testable import SingleThread`. `@MainActor` per-struct where needed (target has no `SWIFT_DEFAULT_ACTOR_ISOLATION`). Platform split by CI destination, not `#if`.
Known relevant: `PrivacySettingsContentTests.swift` (4 disclosure sections, "no analytics" claim, localized resolution), `AppGroupTests.swift` (stable defaults instance), `AppDelegateTests.swift`, `EntitlementStoreTests.swift`, fixtures `TestFixtures.swift`/`BackgroundTestFixtures.swift`/`StubBundle.swift`/`LocalizationTestHelpers.swift`.

### Testing seams for UI flows
- iOS UI tests (`SingleThreadUITests`, XCTest): launch-arg `--seed '<json>'` backed by `InMemoryEventStore` drives deterministic write flows; no real `EKEventStore`/TCC prompt. UI tests are the exception, not the default — justify each.
- watchOS: `--ui-testing` seam.

### Platform gating
- iOS unit: simulator matrix (iPhone 17, iPad A16).
- macOS unit: `-destination "platform=macOS"`, `CODE_SIGNING_ALLOWED=NO`.
- watch unit/UI: separate jobs, paired sims (`simulator-pairing` skill).

## Build / Verify Gotchas
- **Warnings-as-errors**: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide, scoped per-target in pbxproj only (never CLI flags). Gate fails on `<path>:<line>:<col>: warning:` not allowlisted (scripts/xcodebuild-warnings.allow, one-line rationale).
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** on iOS + watch app targets only (not SingleThreadCore, tests, widget). Async functions there default `@MainActor`; don't wrap in `Task { @MainActor in }`.
- **Swift 6** (`SWIFT_VERSION = 6.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`); Shared SPM package `swift-tools-version: 6.0`, floors iOS 17.0 / watchOS 11.0 / macOS 26.5.
- **`DEBUG_INFORMATION_FORMAT`**: Debug `dwarf` (fast incremental), Release `dwarf-with-dsym` (project pbxproj Debug:651 / Release:714). Only Release emits dSYMs (relevant for symbolication).
- **verify_deployment_target()** (scripts/test.sh:158-258) scans pbxproj `*_DEPLOYMENT_TARGET` and SingleThreadCore Package.swift floors; split before changing any floor.
- **verify_xcodebuild_wrapped()** (test.sh:136-153) fails on any bare `xcodebuild` not routed through `run_xcodebuild`.
- **Gate ordering** (test.sh): swiftformat+fix → lint → swiftlint --strict → warning self-test → iOS build-for-testing → watch build → periphery --strict → UI → watch UI → macOS unit tests.
- **Local-only pre-existing failures**: three `EntitlementStoreTests` fail on this Mac (`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`) — annotate as pre-existing, don't debug. Never `git stash` to baseline.
- **`AppGroup.defaults`** must round-trip through the App Group suite (`UserDefaults(suiteName:)`), never `UserDefaults.standard` (simulator diverges silently). Single cached instance (AppGroupTimer `defaultsIsAStableInstance`).
- **New source .swift files need no pbxproj edit** (synchronized file groups). A **new test target** DOES: pbxproj IDs, scheme TestAction, `-only-testing` entry in scripts/test.sh, CI matrix entries.
- **CI** (`.github/workflows/ci.yml`): jobs gated to main push + dependabot PRs; macos-26 / Xcode 26.6; unit matrix 2 devices with `-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`; cache keyed on DerivedData + source hashes. Every xcodebuild log → check-warnings.sh.
- **Xcode 27 (local) vs 26.6 (CI)** divergence (e.g. `$`-projection-only `@State`): CI-green may not reproduce locally — see `periphery` skill.
- **Release archive only needs dSYM handling; that pathway is Xcode Cloud.** No `ci_scripts/` exists; no `.xcprivacy` exists anywhere.
