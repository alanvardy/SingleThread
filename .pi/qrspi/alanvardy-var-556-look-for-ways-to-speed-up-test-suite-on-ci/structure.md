# Structure Outline

## Approach

Make the CI `test` job compile the app **once** (build-for-testing → test-without-building against a shared explicit DerivedData path), convert `SingleThreadTests` from an app-hosted bundle into a non-hosted logic bundle that compiles `ReminderFilter.swift` directly, fix the DerivedData cache key so any meaningful change invalidates it, and pin + cache the lint tools. Each change keeps `ci.yml`, `Makefile`, and `scripts/test.sh` byte-identical for shared commands. **Prerequisite: capture a baseline** — CI timings are not recorded anywhere, so the first action is a baseline run of today's `ci.yml`, then re-measure after each phase.

## Phase 1: Single-compile build/test pipeline

Replaces the two separate `xcodebuild build` + `xcodebuild test` invocations (which compile the app twice) with a `build-for-testing` / `test-without-building` pair pointed at an explicit shared `-derivedDataPath`, mirrored across CI, the Makefile, and `scripts/test.sh`.

**Files**: `.github/workflows/ci.yml`, `Makefile`, `scripts/test.sh`

**Key changes**:
- CI Build step — `xcodebuild -scheme SingleThread -destination "$SIM" -configuration Debug -derivedDataPath "$DERIVED_DATA" build-for-testing -only-testing:SingleThreadTests`
- CI test step — `xcodebuild -scheme SingleThread -destination "$SIM" -derivedDataPath "$DERIVED_DATA" test-without-building -only-testing:SingleThreadTests`
- New shared path constant: CI `DERIVED_DATA="$GITHUB_WORKSPACE/DerivedData"`; local `DERIVED_DATA="DerivedData"` (already gitignored at `.gitignore:4`)
- `Makefile`: `build` → `build-for-testing`; `test` → `test-without-building` (same `-only-testing:SingleThreadTests` filter); add `DERIVED_DATA` var
- `scripts/test.sh`: same two-step split for the "Building…" / "Unit tests…" sections

**Verify**: `./scripts/test.sh` passes locally (still app-hosted — tests unchanged); CI `test` job wall-clock drops measurably vs. the recorded baseline (build no longer runs twice). Manual: confirm the CI log shows a single "Build" phase and `test-without-building` finds the bundle (no "no test bundle" error).

---

## Phase 2: De-host the unit tests (logic bundle)

Converts `SingleThreadTests` from an app-hosted bundle into a non-hosted logic bundle that compiles `ReminderFilter.swift` directly, so the test target no longer depends on the app (or EventKit-coupled `ReminderStore`) at all.

**Files**: `SingleThread.xcodeproj/project.pbxproj`, `SingleThreadTests/SingleThreadTests.swift`

**Key changes**:
- Add `SingleThread/ReminderFilter.swift` as an additional member of the `SingleThreadTests` target — a `membershipException` entry on the `SingleThread` synchronized root group (`PBXFileSystemSynchronizedBuildFileExceptionSet` → `SingleThreadTests` target). No file moves.
- Remove from the test target's Debug **and** Release configs: `BUNDLE_LOADER = "$(TEST_HOST)"` (`project.pbxproj:481,506`) and `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThread.app/…"` (`:499,524`)
- Remove `TestTargetID = 51AA3ED5302D5C4500960DFC` from the `SingleThreadTests` TargetAttributes (`:181`); keep it on `SingleThreadUITests` (`:185`)
- `SingleThreadTests.swift`: drop `@testable import SingleThread` (`:9`); keep `import Foundation` + `import Testing`. All 7 tests now exercise the copy of `dueStatus` compiled into the test module.

**Verify**: `make build` then `make test` both pass; `./scripts/test.sh` passes. Manual: open the project in Xcode, confirm the test target builds as a `.xctest` without the app in its `TEST_HOST`, and the 7 tests still pass with unchanged expectations. (Risk: Xcode may rewrite pbxproj IDs on the membership edit — verify the project still opens/builds.)

---

## Phase 3: Correct the DerivedData cache key

Makes the cache restore the explicit `$GITHUB_WORKSPACE/DerivedData` path (from Phase 1) and invalidates on any meaningful change — test sources, entitlements, asset catalog, and `project.pbxproj` — using the Xcode version derived from `setup-xcode` instead of the hardcoded `xcode26.6`.

**Files**: `.github/workflows/ci.yml`

**Key changes**:
- `setup-xcode` step gains `id: xcode`; cache key reads `steps.xcode.outputs.version`
- Cache `path: ${{ github.workspace }}/DerivedData` (replaces the `~/Library/…/SingleThread-*` glob)
- Key: `derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThread.xcodeproj/project.pbxproj') }}`
- Restore key: `derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-`

**Verify**: two back-to-back CI runs on the same commit → second run reports a cache hit. Manual: open a PR changing only `SingleThreadTests/SingleThreadTests.swift` and confirm the cache misses (no stale-artifact false pass); confirm a pure `SingleThread/**/*.swift` change still invalidates.

---

## Phase 4: Pin and cache lint tools

Removes the unpinned, uncached `brew install swiftlint swiftformat` from the `lint` job, replacing it with version-pinned tools restored from cache — deterministic and fast. SwiftFormat/SwiftLint invocations stay byte-identical.

**Files**: `.github/workflows/ci.yml`, `.mise.toml` (new)

**Key changes**:
- New lockfile `.mise.toml` pinning both tools (e.g. `[tools] swiftlint = "<ver>"; swiftformat = "<ver>"`) — exact versions chosen during implementation
- `Install tools` step → `mise install` (provision from lockfile) instead of `brew install`
- Cache `~/.local/share/mise`, key `lint-tools-${{ runner.os }}-${{ hashFiles('.mise.toml') }}`

**Verify**: `lint` job passes with `swiftformat --lint …` and `swiftlint lint --strict --config .swiftlint.yml` (unchanged commands). Manual: two CI runs → tool install is a cache hit; bumping a version in `.mise.toml` forces a fresh install.

---

## Testing Checkpoints

- **After Phase 1**: `./scripts/test.sh` and `make build && make test` are green and byte-match CI's build/test commands. CI compiles once; `test` job is faster than baseline.
- **After Phase 2**: `SingleThreadTests` builds as a non-hosted `.xctest`; the 7 tests pass unchanged; no `TEST_HOST`/`BUNDLE_LOADER`/`TestTargetID` on the unit target; project opens in Xcode.
- **After Phase 3**: Cache restores `$GITHUB_WORKSPACE/DerivedData`; edits to test sources or `project.pbxproj` invalidate the key (no stale pass); Xcode version bump auto-invalidates.
- **After Phase 4**: Lint tools install from cache, pinned by `.mise.toml`; lint job deterministic.

## Notes on sliceability

- **Phase 3 is CI-only** (single layer): cache key/path correctness is self-contained in `ci.yml`; there is no local/`scripts/test.sh` counterpart to mirror. Still independently verifiable end-to-end.
- **Phase 2 must touch pbxproj + test source together** — the membership edit and the `@testable import` removal are one atomic change; splitting them leaves a broken build. Accepted as a single slice.
- **Simulator boot is intentionally not addressed** (Design Decision 5); a future `platform=macOS` destination would remove it entirely but is out of scope here.
