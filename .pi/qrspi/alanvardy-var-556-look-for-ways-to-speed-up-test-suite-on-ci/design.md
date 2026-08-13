# Design Discussion

## Current State

### CI pipeline (`.github/workflows/ci.yml`, 56 lines)
- One workflow `CI` (`ci.yml:1`), triggers `push` + `pull_request` to `main` (`ci.yml:3-7`).
- Two jobs with no `needs:` — `test` (`ci.yml:10`) and `lint` (`ci.yml:42`) run in
  parallel on `macos-26` (`ci.yml:11`, `:43`).
- `test` job: checkout (`:13`) → `setup-xcode` pinned to `26.6` (`:15-17`) → clear
  `DEVELOPMENT_TEAM` (`:19-20`) → DerivedData cache (`:22-26`) → **Build** (`:28-33`,
  20m) → **Unit tests** (`:35-40`, 20m).
- `lint` job: checkout (`:45`) → `brew install swiftlint swiftformat` (`:47-48`) →
  SwiftFormat `--lint` (`:50-52`) → SwiftLint `--strict` (`:54-56`).

### Why the test job is slow
1. **Duplicate compilation.** Build and test are two separate `xcodebuild`
   invocations — `build` (`ci.yml:31-33`) then `test` (`ci.yml:38-40`). The `test`
   action re-runs its own build phase, so the app compiles twice per run. There is no
   `build-for-testing` / `test-without-building` split.
2. **App-hosted unit tests.** The `SingleThreadTests` bundle is hosted inside the app:
   `TEST_HOST` + `BUNDLE_LOADER` in its Debug (`project.pbxproj:481,499`) and Release
   (`:506,524`) configs, plus `TestTargetID` (`:181`). `@testable import SingleThread`
   (`SingleThreadTests.swift:9`) requires `ENABLE_TESTABILITY=YES`
   (`project.pbxproj:309`) and a full app build — including the EventKit-coupled
   `ReminderStore` — just to run 7 pure tests. The tests only exercise `dueStatus`
   (`ReminderFilter.swift:15`), a `nonisolated` function depending only on `Foundation`.
3. **Weak cache.** The cache key (`ci.yml:25`) hashes only `SingleThread/**/*.swift` —
   test sources, `project.pbxproj`, entitlements, and asset catalogs are outside the
   hash, and the Xcode version is hardcoded as `xcode26.6`. The cached path is the
   glob `~/Library/Developer/Xcode/DerivedData/SingleThread-*` (`ci.yml:24`).
4. **Lint tool install.** `brew install` is unpinned and uncached (`ci.yml:48`).

### Test composition
- Unit tests (`SingleThreadTests/SingleThreadTests.swift`): 7 Swift Testing `@Test`
  functions (`:15,25,34,44,54,64,74`), all calling `dueStatus` and asserting with
  `#expect`/`#require`. Only `dueStatus` is covered.
- UI tests (`SingleThreadUITests/`): XCTest, launch-only, **never run in CI** (excluded
  by `-only-testing:SingleThreadTests` in `ci.yml:40`, `Makefile:9`, `scripts/test.sh:32`).

## Desired End State

The `test` job compiles the app **once** and runs a cheap, non-app-hosted test bundle;
the cache key correctly invalidates on any meaningful change; the `lint` job installs
pinned tools from cache. Verification:

1. `test` job wall-clock drops measurably vs. today's baseline. **We do not have a
   recorded baseline** — CI timings and cache hit-rate are not stored anywhere in the
   repo (research "Open Areas"). First step of implementation is to record a baseline
   run, then compare after each change.
2. `scripts/test.sh` (local, `:24-32`) and `make build`/`make test` (`Makefile:5-9`)
   produce the **same result** as CI for the shared commands; no behavioral drift.
3. Changing `project.pbxproj` or a test source invalidates the DerivedData cache and
   triggers a fresh (correct) build — no stale-artifact false-pass.
4. The 7 unit tests still pass, unchanged in behavior, now without the app target.

## Patterns to Follow

- **Shared command strings.** Build/test/lint commands are byte-identical across
  `ci.yml`, `Makefile`, and `scripts/test.sh` (`ci.yml:31-33/38-40` ==
  `Makefile:6/9` == `scripts/test.sh:24-26/30-32`). Keep it that way: any new
  `build-for-testing`/`test-without-building` split must be mirrored in `scripts/test.sh`
  and the Makefile so local == CI.
- **Swift Testing for unit tests, XCTest for UI tests.** Unit tests use
  `import Testing` + `@Test` (`SingleThreadTests.swift:10,15`); UI tests use XCTest
  (`SingleThreadUITests.swift:8`). New test code keeps this split.
- **Pure-logic extraction.** The codebase already isolates pure logic in
  `ReminderFilter.swift` (top-level `nonisolated` func, `:15`), separate from the
  EventKit-coupled `ReminderStore.swift`. We follow that by making the test bundle
  compile `ReminderFilter.swift` directly rather than reaching through the app.
- **Synchronized file groups.** `objectVersion = 77` (`project.pbxproj:6`) auto-discovers
  `.swift` files per directory (see `AGENTS.md` "Adding New Files"). Target-membership
  changes for `ReminderFilter.swift` are the one pbxproj edit needed; no file moves.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION` scoping.** It is set **only on the app target**
  (`project.pbxproj:425,470`), not on test targets. `dueStatus` is already `nonisolated`,
  so compiling it into the test module changes nothing about isolation.

### Patterns NOT to follow
- **The current DerivedData glob cache** (`ci.yml:24`) — path globs with Xcode's
  hashed `SingleThread-<hash>` folder are fragile. Replace with an explicit
  `-derivedDataPath`.
- **Duplicating the destination string** in three places (`ci.yml:32/39`,
  `Makefile:1`, `scripts/test.sh:5`) with no `OS=` pin. Do not extend this duplication
  further; we are not pinning `OS=` (see Decision 5).
- **`.swiftformat:19` says `--exclude SingleThreadUITests`, yet every invocation still
  passes `SingleThreadUITests/` explicitly** (`ci.yml:52`, `Makefile:15/19`,
  `scripts/test.sh:11/16`). Don't propagate this redundancy into new commands.

## Design Decisions

1. **Build/test split — `build-for-testing` + `test-without-building`** (Q1 → A).
   The Build step becomes `xcodebuild build-for-testing … -only-testing:SingleThreadTests`
   (builds the app + unit bundle once, skips the UI bundle); the test step becomes
   `xcodebuild test-without-building … -only-testing:SingleThreadTests`. Both point at a
   shared explicit `-derivedDataPath` (e.g. `$GITHUB_WORKSPACE/DerivedData`) that the
   cache restores. Keeps a distinct build signal (compile errors before test failures)
   while removing the second compile. Chosen over a single `xcodebuild test` because we
   want the standalone "does it build" gate.

2. **Unit tests become a logic (non-hosted) bundle** (Q2 → B).
   Add `ReminderFilter.swift` as an additional member of the `SingleThreadTests` target
   (synchronized-group membership edit), drop `@testable import SingleThread` in favor of
   `import Foundation` (`SingleThreadTests.swift:9`), and remove `BUNDLE_LOADER`/
   `TEST_HOST` from the test target's Debug/Release configs (`project.pbxproj:481,499,
   506,524`) and `TestTargetID` (`:181`). The test step no longer builds the app; the
   app still builds in step 1 as the compile gate. Chosen over a framework target (Q2 C)
   to keep the change minimal; revisit C if pure logic grows beyond `dueStatus`.

3. **Cache key — explicit path + full hash + derived Xcode version** (Q3 → A).
   Cache the explicit `-derivedDataPath`. Key =
   `derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThread.xcodeproj/project.pbxproj') }}`
   (give the `setup-xcode` step an `id` and use its `version` output instead of the
   hardcoded `xcode26.6`). `SingleThread/**` covers the entitlements
   (`SingleThread/SingleThread.entitlements`) and asset catalog; `project.pbxproj` is
   included explicitly since it lives under `SingleThread.xcodeproj/`. Restore key is the
   `derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-` prefix.

4. **Lint tools — pin + cache** (Q4 → A).
   Pin `swiftlint` and `swiftformat` versions via a lockfile (e.g. `mise`, matching the
   `brew` tools already used at `ci.yml:48`) and cache the tool directory with
   `actions/cache`. Keeps the lint job deterministic and removes the per-run install.
   No change to the SwiftFormat/SwiftLint invocations themselves (`ci.yml:52,56`).

5. **Simulator — leave as-is** (Q5 → C). No `OS=` pin, no `simctl` preboot. The
   xcodebuild on-demand boot stays; we accept boot latency rather than duplicating the
   destination string further. Noted as a future micro-optimization.

## What We're NOT Doing

- **No UI test execution in CI.** `SingleThreadUITests` stays excluded
  (`-only-testing:SingleThreadTests`); we only stop *building* it in step 1.
- **No Release build/test path.** Debug-only remains (`ci.yml:31-33`); Release settings
  (`project.pbxproj:368,384`) are untouched.
- **No new framework/library target** (Q2 C is deferred). No restructuring beyond
  target membership.
- **No simulator pinning or preboot** (Q5 C). No `OS=` in destinations.
- **No test parallelization / sharding.** With 7 pure tests, execution time is
  negligible; the wins are all on the build side.
- **No `ReminderStore`/EventKit test coverage** — out of scope for this speed-up task;
  that write path can't run in CI (`AGENTS.md` "Reminders").
- **No macOS test destination** — even though `SUPPORTED_PLATFORMS` includes `macosx`
  (`project.pbxproj:493`), we keep the iOS-simulator destination to avoid behavioral
  drift from local/CI divergence.

## Open Risks

- **Baseline is unknown.** CI timings aren't recorded in the repo, so "faster" can't be
  quantified until we capture a baseline. Record before/after per step.
- **`test-without-building` + cache staleness.** If the cache restore is incomplete or
  the key drifts, `test-without-building` can fail with "no test bundle" or run stale
  binaries. The full-hash key (Decision 3) mitigates this; watch for partial-restore
  edge cases on `runner.os`/version prefix matches.
- **Synchronized-group membership edit.** Adding `ReminderFilter.swift` to the test
  target is a pbxproj change (an "additional member" exception); Xcode may rewrite
  surrounding IDs. Verify the project still opens/builds after the edit.
- **`@testable import` removal changes module boundaries.** Once `dueStatus` is compiled
  into `SingleThreadTests`, tests no longer exercise the app's *compiled copy* of
  `ReminderFilter.swift` — a later divergence between the two copies is a (small) risk.
  The app still compiles `ReminderFilter.swift` in step 1, so compile errors still
  surface there.
- **Xcode version coupling.** Deriving the cache key from `setup-xcode`'s output (Decision
  3) means a toolchain bump automatically invalidates the cache — desired, but confirm
  that action's `version` output format matches expectations before relying on it.
- **Logic bundle still boots a simulator.** iOS logic tests run in a simulator process,
  so boot cost remains; it just no longer includes an app build. A future `platform=macOS`
  destination would remove the simulator entirely but is out of scope.
