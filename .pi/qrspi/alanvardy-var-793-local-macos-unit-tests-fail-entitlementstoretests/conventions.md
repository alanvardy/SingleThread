# Conventions — Shared Factual Appendix

For Design/Structure/Plan. Do not re-open the sources cited here unless specifics beyond this appendix are needed. All line refs are to the current branch state.

## Canonical Commands

| Task | Command | Source |
|---|---|---|
| Full gate (CI-identical) | `./scripts/test.sh` | `scripts/test.sh:1-4` |
| Unit-only gate | `./scripts/test.sh --unit-only` / `make test` | `Makefile:88-92`; `scripts/test.sh:311-330` |
| UI-only gate | `./scripts/test.sh --ui-only` / `make ui-test` | `Makefile:94-97` |
| iOS build | `make build` (or `./scripts/test.sh` full pipeline) | `Makefile:14-15` |
| macOS build | `make mac-build` | `Makefile:23-24` |
| macOS unit tests | `make mac-test` — `xcodebuild -scheme SingleThread -destination '$(MAC_SIM)' -derivedDataPath '$(DERIVED_DATA)' CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests` | `Makefile:26-27` |
| Lint | `make lint` (SwiftFormat `--lint` + SwiftLint `--strict`) | `Makefile:62-65` |
| Format | `make format` (SwiftFormat + `swiftlint --fix`) | `Makefile:67-70` |
| Periphery | `make periphery` (`periphery scan --strict`) | `Makefile:72-73` |
| Coverage | `make coverage` / `coverage-ui` / `coverage-all` (xccov view) | `Makefile:33-62` |
| macOS run | `make mac-run` (build + `open` the .app) | `Makefile:29-32` |

## macOS Unit-Test Invocations (Local vs CI)

- Local: `scripts/test.sh:286-292` — `-destination "platform=macOS"`, `-configuration Debug`, `CODE_SIGNING_ALLOWED=NO`, `test -only-testing:SingleThreadTests`, repo-relative `DerivedData` (`test.sh:10-12`). Runs last in the full pipeline, after iOS unit/UI tests in the same shell. No `-resultBundlePath`.
- `make mac-test` (`Makefile:26-27`): same minus `-configuration Debug`.
- CI `mac-tests` (`.github/workflows/ci.yml:270-320`): `macos-26` runner, Xcode 26.6 (`:277-280`), `DEVELOPMENT_TEAM=` override (`:282`), DerivedData cache via `actions/cache@v4` (`:284-292`), build step with `-showBuildTimingSummary` (`:293-302`), test step with `-resultBundlePath TestResults-mac.xcresult` (`:304-313`), upload artifact on failure (`:315-320`).
- **Gotchas**: destination name-only `platform=macOS` is unambiguous locally (no runtime ambiguity); iOS sim destination is NOT — `scripts/test.sh:1-34` resolves `iPhone 17` name → UDID and pre-boots (`resolve_sim_udid`, `preboot_sim`). One xcodebuild test process at a time (simulator contention). CI caches only DerivedData — StoreKit/storekitd state never carries over; local host state does (long-lived sandbox container).

## Test-Suite Inventory (`SingleThreadTests/` — Swift Testing)

75 test files, ~506 `@Test` functions. Only `SingleThreadTests/EntitlementStoreTests.swift` imports StoreKit (`import StoreKitTest`). ~50 files are `@MainActor`; 16 use `@Suite(.serialized)` (StoreKit/EKEventStore/UserDefaults/timer-sensitive suites).

Platform gating (`#if os(...)` present): `AppDelegateTests.swift`, `RescheduleSyncTests.swift`, `SkippedReminderSyncServiceTests.swift`, `EnableActionButtonsSyncTests.swift`, `MacOSActionButtonChromeTests.swift`, `SettingsSubscreenLayoutTests.swift`, `AboutViewTests.swift`, `EntitlementSyncTests.swift`, `BackgroundCardTests.swift`, `MicrophoneToggleTests.swift` (+ others; grep `#if os(` for the full set).

### Entitlement / StoreKit
- `EntitlementStoreTests.swift` (~121 lines) — `@MainActor @Suite(.serialized)` (`:7-8`), 8 tests. 4 never touch StoreKit (real-init ×2, seams ×2); 3 create `SKTestSession(configurationFileNamed: "Products")` + `disableDialogs = true` as per-test locals. A private `wait(for:timeout:)` helper (`async throws`, 50 ms steps, ≤ 2 s) polls `hasResolvedEntitlement` and both async StoreKit tests await it. The `hostStoreKitIsClean` canary reads the real host `Transaction.currentEntitlements` and fails with an actionable reset message when it holds entitled transactions. No setUp/tearDown, no `clearTransactions()`. The 3 macOS-sensitive tests: `isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean`.
- `EntitlementSyncTests.swift` — `@Suite(.serialized)`, watch sync of the flag (no StoreKit).
- `UITestingSeedTests.swift` — `@Suite(.serialized)`, seed JSON parsing/materialization.

### StoreKit config
- `SingleThread/Products.storekit` — single non-consumable `app.alanvardy.SingleThread.unlimited` @ USD 2.99. Single source of truth for the ID: `EntitlementStore.unlockProductID` (`EntitlementStore.swift:49-51`); keep storekit file + `StoreKitConfigurationFileReference` in sync (`AGENTS.md` Purchases section; `.pi/skills/storekit/SKILL.md:1-20`).
- Scheme: `StoreKitConfigurationFileReference` in **LaunchAction only** (`SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme:90-92`). TestAction (`:39-69`) has no reference, no Pre/PostActions, no env vars. No `*.xctestplan` files exist.
- Discovery: zero pbxproj refs to `Products.storekit`; bundled via synchronized-folder resource of the app target (`project.pbxproj:257-259`); `SingleThreadTests` is hosted in `SingleThread.app` (`TEST_HOST` `pbxproj:860/:889`, `BUNDLE_LOADER` `:838/:867`), so `SKTestSession(configurationFileNamed:"Products")` resolves from the host app bundle's resources.
- No `com.apple.developer.in-app-purchases` entitlement anywhere; test target relaxes only `SWIFT_TREAT_WARNINGS_AS_ERRORS = NO` (`pbxproj:853-856, :882-885`).

## State-Reset Conventions

- **Real reset**: `UITestingSeed.resetPersistedState()` (`UITestingSeed.swift:62-69`) — removes all 24 `persistedKeys` (`:73-98`, list quoted in research.md Q6) from `AppGroup.defaults` AND `UserDefaults.standard`. Wired at `AppViewModel.swift:275` inside `seededStore`, called only on `--seed` launches; seeded writes re-touch AppGroup only (`:287, :291, :295`).
- **Micro resets**: `--ui-testing` + `--reset-glow-preference` / `--reset-swipe-preference` remove single keys from `.standard` only (`AppViewModel.swift:216-222`).
- **Unit tests**: per-key `defer { removeObject(forKey:) }` on `.standard` / both stores — e.g. `MicrophoneToggleTests.swift:77…`, `ReminderStoreTests.swift:905…`, `EnableActionButtonsMigrationTests.swift:18-19`. Watch: `ShowCompletionGlowStateTests.swift:35…`, `WatchSyncPipelineTests.swift:537,552`.
- **Not covered by any reset**: keychain (zero usage), StoreKit transaction store, storekitd — no reset code exists for those anywhere in the repo; `isEntitled` is transient in-memory (`EntitlementStore.swift:58, 111-112`).

## Build/Verify Gotchas

- `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` project-wide; warnings fail everywhere. macOS tests run unsigned (`CODE_SIGNING_ALLOWED=NO`) — correlated with local SKTestSession isolation failure (`var-796/implement.md:46`).
- Local macOS unit tests are environment-sensitive: host StoreKit sandbox state leaks into `Transaction.currentEntitlements` (3 tests fail locally when the host resolves `isEntitled=true`; CI green). Documented chain: var-781/789/792/794/796. Prior probes: `clearTransactions()` in-test passed only in isolation (`var-789/plan.md:297`); `AppStore.sync()` in-suite hangs after prior sessions wedge storekitd (`var-642/implement.md:35`); `storekitd` restart ineffective; `SKServiceErrorDomain Code=2` saving config on this host.
- Watch tests need `lib_TestingInterop.dylib` embedded into the runner locally (`scripts/test.sh` "Local-only fix" block) — irrelevant to macOS unit stage.
- XCTestDevices cleanup: `scripts/test.sh` prunes runtimes older than `RUNTIME_AGE_HOURS` (default 1 h) from `~/Library/Developer/XCTestDevices` to reclaim space.
- Unit-test naming: Swift Testing test names must not start with `test`/`testing` (SwiftFormat strips them under `make format`); UI (XCTest) names keep `test…` and are format-excluded.
- StoreKitTest headers trip an iOS-18-deprecated-symbol warning — the reason the test target (the only StoreKitTest importer) relaxes warnings-as-errors (`pbxproj:853-856` comment).