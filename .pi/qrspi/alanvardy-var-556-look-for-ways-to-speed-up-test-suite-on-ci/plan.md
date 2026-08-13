# Implementation Plan

## Overview

Make the CI `test` job compile the app **once** (`build-for-testing` → `test-without-building` against an explicit shared DerivedData path), de-host the unit tests into a non-hosted logic bundle, fix the DerivedData cache key, and pin + cache the lint tools. Shared commands stay byte-identical across `ci.yml`, `Makefile`, and `scripts/test.sh`; the 7 unit tests pass unchanged throughout.

---

## Prerequisite: Capture the CI baseline

CI timings are not recorded anywhere in the repo, so "faster" cannot be quantified until a baseline exists. Capture it **before** Phase 1, then re-measure after each phase.

### Changes

None — observation only.

### Verification

#### Manual
- [ ] On the current `main` (today's `ci.yml`), trigger one `CI` run (push or open a throwaway PR).
- [ ] Record these numbers from the GitHub Actions run summary (save to a scratch note, not committed):
  - [ ] `test` job total wall-clock
  - [ ] `Build` step duration
  - [ ] `Unit tests` step duration
  - [ ] `lint` job total wall-clock
- [ ] Note the actions/cache result ("Cache hit" vs "Cache miss") on the `test` job.

---

## Phase 1: Single-compile build/test pipeline

Replace the two separate `xcodebuild build` + `xcodebuild test` invocations (which compile the app twice) with a `build-for-testing` / `test-without-building` pair pointed at a shared explicit `-derivedDataPath`, mirrored across CI, the Makefile, and `scripts/test.sh`. Tests are still app-hosted in this phase — this is purely the build/test split.

### Changes

#### 1. `.github/workflows/ci.yml` — test job env + build/test steps
**File**: `.github/workflows/ci.yml`
**Action**: modify

Add a job-level `env:` block (new `SIM` and `DERIVED_DATA`), and rewrite the `Build` and `Unit tests` steps to use `build-for-testing` / `test-without-building` with `-derivedDataPath "$DERIVED_DATA"`. The `setup-xcode` step, `Override development team` step, and the cache step are **unchanged in this phase**.

```yaml
  test:
    runs-on: macos-26
    env:
      SIM: platform=iOS Simulator,name=iPhone 17
      DERIVED_DATA: ${{ github.workspace }}/DerivedData
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '26.6'

      - name: Override development team
        run: echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV

      - uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData/SingleThread-*
          key: derived-data-${{ runner.os }}-xcode26.6-${{ hashFiles('SingleThread/**/*.swift') }}
          restore-keys: derived-data-${{ runner.os }}-xcode26.6-

      - name: Build
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadTests

      - name: Unit tests
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -derivedDataPath "$DERIVED_DATA" \
            test-without-building \
            -only-testing:SingleThreadTests
```

Note: the cache step still points at the old glob path in this phase (fixed in Phase 3), so cache is temporarily ineffective between Phases 1–2. That is expected and acceptable for an independently-verifiable slice.

#### 2. `Makefile` — build/test split + `DERIVED_DATA` var
**File**: `Makefile`
**Action**: modify

```make
SIM := platform=iOS Simulator,name=iPhone 17
DERIVED_DATA := DerivedData

.PHONY: build test clean lint format

build:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -configuration Debug -derivedDataPath '$(DERIVED_DATA)' build-for-testing -only-testing:SingleThreadTests

test:
	xcodebuild -scheme SingleThread -destination '$(SIM)' -derivedDataPath '$(DERIVED_DATA)' test-without-building -only-testing:SingleThreadTests

clean:
	xcodebuild -scheme SingleThread -destination '$(SIM)' clean

lint:
	swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint lint --strict --config .swiftlint.yml

format:
	swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
	swiftlint --fix --config .swiftlint.yml
```

**Behavior change to note**: `make test` now requires a prior `make build` (it runs `test-without-building`, which fails with "no test bundle found" if nothing was built). The canonical local sequence is `make build && make test`. `make clean` is left unchanged (it targets the default DerivedData location; clear the explicit path with `rm -rf DerivedData`).

#### 3. `scripts/test.sh` — two-step split for "Building…" / "Unit tests…"
**File**: `scripts/test.sh`
**Action**: modify

Add `DERIVED_DATA="DerivedData"` to the configuration block and split the build/test invocations exactly as CI does.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SIM="platform=iOS Simulator,name=iPhone 17"
SCHEME="SingleThread"
DERIVED_DATA="DerivedData"

cd "$(dirname "$0")/.."

echo "==> Formatting…"
swiftformat SingleThread/ SingleThreadTests/ SingleThreadUITests/
swiftlint --fix --config .swiftlint.yml

echo ""
echo "==> SwiftFormat check…"
swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/

echo ""
echo "==> SwiftLint…"
swiftlint lint --strict --config .swiftlint.yml

echo ""
echo "==> Building…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  -only-testing:SingleThreadTests

echo ""
echo "==> Unit tests…"
xcodebuild -scheme "$SCHEME" \
  -destination "$SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadTests

echo ""
echo "✅ All CI checks passed."
```

### Verification

#### Automated
- [x] `make build && make test` passes locally (7 tests green, still app-hosted).
- [x] `./scripts/test.sh` passes locally.
- [x] `git diff` confirms the `xcodebuild` build/test command strings (flags and order) match across `ci.yml`, `Makefile`, and `scripts/test.sh` — only the variable syntax differs (`$SIM`/`"$SIM"`/`'$(SIM)'`).

#### Manual
- [ ] CI `test` job `Build` step runs `build-for-testing` and the log shows a **single** Build phase (no second compile).
- [ ] CI `Unit tests` step runs `test-without-building` and finds the bundle — no "no test bundle found" / "Failed to locate test bundle" error.
- [ ] Compare the `test` job wall-clock against the recorded baseline: it should drop measurably (the app is no longer compiled twice).

---

## Phase 2: De-host the unit tests (logic bundle)

Convert `SingleThreadTests` from an app-hosted bundle into a non-hosted logic bundle that compiles `ReminderFilter.swift` directly. This is one atomic slice — the pbxproj membership edit and the `@testable import` removal must land together or the build breaks.

### Changes

#### 1. `project.pbxproj` — add `ReminderFilter.swift` as an additional member of `SingleThreadTests`
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

Two edits: add an `exceptions` entry to the `SingleThread` synchronized root group, and add a new `PBXFileSystemSynchronizedBuildFileExceptionSet` section (which goes alphabetically between the `PBXFileReference` and `PBXFileSystemSynchronizedRootGroup` sections).

Use a new unique 24-hex-char object ID; `51AA3F02302D5C4500960DFC` is free (highest existing is `51AA3F01…`).

Edit 1a — root group:

```diff
 		51AA3ED8302D5C4500960DFC /* SingleThread */ = {
 			isa = PBXFileSystemSynchronizedRootGroup;
+			exceptions = (
+				51AA3F02302D5C4500960DFC /* Exceptions for "SingleThread" folder in "SingleThreadTests" target */,
+			);
 			path = SingleThread;
 			sourceTree = "<group>";
 		};
```

Edit 1b — new section, inserted between the `PBXFileReference` and `PBXFileSystemSynchronizedRootGroup` sections:

```diff
 /* End PBXFileReference section */
 
+/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
+		51AA3F02302D5C4500960DFC /* Exceptions for "SingleThread" folder in "SingleThreadTests" target */ = {
+			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
+			membershipExceptions = (
+				ReminderFilter.swift,
+			);
+			target = 51AA3EE4302D5C4500960DFC /* SingleThreadTests */;
+		};
+/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */
+
 /* Begin PBXFileSystemSynchronizedRootGroup section */
```

Semantics: because the exception set's `target` (`SingleThreadTests`) differs from the group's owning target (`SingleThread`), this is an **inclusion** — `ReminderFilter.swift` is now compiled into *both* the app (unchanged, the compile gate) and the test bundle. No file moves.

#### 2. `project.pbxproj` — remove `BUNDLE_LOADER` / `TEST_HOST` from the test target (Debug **and** Release)
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

There are exactly two `XCBuildConfiguration` blocks whose `buildSettings` contain `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThreadTests;` — the test target's Debug (`51AA3EFD…`) and Release (`51AA3EFE…`). In **both**, delete the `BUNDLE_LOADER = "$(TEST_HOST)";` line (first line of `buildSettings`) and the `TEST_HOST = …` line (last line of `buildSettings`).

Debug block (`51AA3EFD…`):

```diff
 		51AA3EFD302D5C4500960DFC /* Debug */ = {
 			isa = XCBuildConfiguration;
 			buildSettings = {
-				BUNDLE_LOADER = "$(TEST_HOST)";
 				CODE_SIGN_STYLE = Automatic;
 				...
 				TARGETED_DEVICE_FAMILY = "1,2";
-				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThread.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SingleThread";
 			};
 			name = Debug;
 		};
```

Release block (`51AA3EFE…`) — identical deletions, with `name = Release;`:

```diff
 		51AA3EFE302D5C4500960DFC /* Release */ = {
 			isa = XCBuildConfiguration;
 			buildSettings = {
-				BUNDLE_LOADER = "$(TEST_HOST)";
 				CODE_SIGN_STYLE = Automatic;
 				...
 				TARGETED_DEVICE_FAMILY = "1,2";
-				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SingleThread.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SingleThread";
 			};
 			name = Release;
 		};
```

(`…` denotes the unchanged middle of the block — leave every other setting in place.)

#### 3. `project.pbxproj` — remove `TestTargetID` from `SingleThreadTests` TargetAttributes (keep it on `SingleThreadUITests`)
**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify

```diff
 					51AA3EE4302D5C4500960DFC = {
 						CreatedOnToolsVersion = 26.6;
-						TestTargetID = 51AA3ED5302D5C4500960DFC;
 					};
 					51AA3EEE302D5C4500960DFC = {
 						CreatedOnToolsVersion = 26.6;
 						TestTargetID = 51AA3ED5302D5C4500960DFC;
 					};
```

**Intentional non-change**: the `SingleThreadTests` target still declares a `PBXTargetDependency` (`51AA3EE7302D5C4500960DFC`) and `PBXContainerItemProxy` (`51AA3EE6302D5C4500960DFC`) on the app. These only *order* the app build ahead of the test bundle during `build-for-testing` (the compile gate we want); they do **not** host or link the app into the bundle. They are left in place.

#### 4. `SingleThreadTests.swift` — drop `@testable import SingleThread`
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify

```diff
 import Foundation
-@testable import SingleThread
 import Testing
```

All 7 tests now exercise the copy of `dueStatus` (and `DueStatus`) compiled directly into the `SingleThreadTests` module. No other test-body changes.

### Verification

#### Automated
- [x] `make build && make test` passes — 7 tests green, now non-hosted.
- [x] `./scripts/test.sh` passes.
- [x] `grep -n "TEST_HOST\|BUNDLE_LOADER" SingleThread.xcodeproj/project.pbxproj` returns nothing (the only host settings were on the unit target).
- [x] `grep -n "TestTargetID" SingleThread.xcodeproj/project.pbxproj` returns exactly one hit (the `SingleThreadUITests` entry).

> **Adaptation**: de-hosting dropped `SingleThreadTests` out of Xcode's *auto-generated* scheme (a non-hosted target has no host association, so `xcodebuild test-without-building -only-testing:SingleThreadTests` failed with “isn't a member of the specified test plan or scheme”). Added a shared scheme `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThread.xcscheme` that explicitly lists `SingleThreadTests` (and `SingleThreadUITests`) in its `TestAction`. The plan didn't mention this file — it's required for the de-hosted target to be runnable.

#### Manual
- [ ] Open the project in Xcode: `SingleThreadTests` target builds as a `.xctest` with **no host application** selected (Target → General → "Host Application: None"), and the Target Membership inspector shows `ReminderFilter.swift` checked for both `SingleThread` and `SingleThreadTests`.
- [ ] Run the `SingleThreadTests` scheme in Xcode — all 7 tests pass with unchanged expectations.
- [ ] Confirm the project still opens/builds cleanly (Xcode may re-sort/re-ID the pbxproj on open; verify no diff noise beyond the intended edits, and that the `exceptions` wiring survived).

---

## Phase 3: Correct the DerivedData cache key

Point the cache at the explicit `$GITHUB_WORKSPACE/DerivedData` path (from Phase 1) and invalidate on any meaningful change — test sources, entitlements, asset catalog, and `project.pbxproj` — using the Xcode version derived from `setup-xcode` instead of the hardcoded `xcode26.6`. CI-only; no local/`scripts/test.sh` counterpart.

### Changes

#### 1. `.github/workflows/ci.yml` — `setup-xcode` id + cache path/key/restore
**File**: `.github/workflows/ci.yml`
**Action**: modify

```diff
       - uses: maxim-lobanov/setup-xcode@v1
+        id: xcode
         with:
           xcode-version: '26.6'
 
       - name: Override development team
         run: echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV
 
       - uses: actions/cache@v4
         with:
-          path: ~/Library/Developer/Xcode/DerivedData/SingleThread-*
-          key: derived-data-${{ runner.os }}-xcode26.6-${{ hashFiles('SingleThread/**/*.swift') }}
-          restore-keys: derived-data-${{ runner.os }}-xcode26.6-
+          path: ${{ github.workspace }}/DerivedData
+          key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThread.xcodeproj/project.pbxproj') }}
+          restore-keys: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-
```

Notes:
- `steps.xcode.outputs.version` is the resolved Xcode version from `maxim-lobanov/setup-xcode@v1` (its `version` output; `xcode-version` is the *input*, not an output). A toolchain bump automatically invalidates the cache.
- `SingleThread/**` covers `SingleThread/SingleThread.entitlements` and `Assets.xcassets`; `project.pbxproj` is hashed explicitly because it lives under `SingleThread.xcodeproj/`.
- This path matches the `-derivedDataPath "$DERIVED_DATA"` used by the build/test steps from Phase 1 (`${{ github.workspace }}/DerivedData`).

### Verification

#### Automated
- [x] `git diff` shows the cache `path` equals `${{ github.workspace }}/DerivedData` and the `-derivedDataPath` in the build/test steps resolves to the same absolute path.

#### Manual
- [ ] Two back-to-back CI runs on the **same commit**: the second run reports a cache **hit** in the `actions/cache` step output.
- [ ] Open a PR that changes **only** `SingleThreadTests/SingleThreadTests.swift`: the cache **misses** (no stale-artifact false pass).
- [ ] Open a PR that changes a file under `SingleThread/**` (e.g. a `.swift` file): the cache **misses**.
- [ ] Confirm the `restore-keys` prefix still allows a partial restore when only the hash segment differs (e.g. after a `project.pbxproj` change), and that `test-without-building` still finds the rebuilt bundle.

---

## Phase 4: Pin and cache lint tools

Remove the unpinned, uncached `brew install swiftlint swiftformat` and replace it with version-pinned tools provisioned from a `.mise.toml` lockfile and restored from cache. The SwiftFormat/SwiftLint invocations themselves stay byte-identical.

### Changes

#### 1. `.mise.toml` (new) — pin both tools
**File**: `.mise.toml`
**Action**: create

```toml
[tools]
swiftlint = "0.59.0"
swiftformat = "0.58.7"
```

**Version selection (do this at implementation time, then hard-code):** determine current stable releases with `mise latest swiftlint` and `mise latest swiftformat` (mise resolves these through its aqua-backed default registry, which pins exact GitHub release versions — unlike the `brew:` backend, which cannot pin). Replace the example numbers above with those values. If plain `swiftlint`/`swiftformat` fail to resolve on the runner, fall back to explicit prefixes: `"aqua:realm/SwiftLint" = "<ver>"` and `"aqua:nicklockwood/SwiftFormat" = "<ver>"`.

#### 2. `.github/workflows/ci.yml` — lint job: install mise, cache tools, `mise install`
**File**: `.github/workflows/ci.yml`
**Action**: modify

```yaml
  lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Install mise
        run: brew install mise

      - name: Cache lint tools
        uses: actions/cache@v4
        with:
          path: ~/.local/share/mise
          key: lint-tools-${{ runner.os }}-${{ hashFiles('.mise.toml') }}

      - name: Install tools
        run: mise install

      - name: Put mise shims on PATH
        run: echo "$HOME/.local/share/mise/shims" >> "$GITHUB_PATH"

      - name: SwiftFormat check
        timeout-minutes: 5
        run: swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/

      - name: SwiftLint
        timeout-minutes: 5
        run: swiftlint lint --strict --config .swiftlint.yml
```

Notes:
- The `SwiftFormat check` and `SwiftLint` run commands are **byte-identical** to before — only the provisioning steps changed.
- `~/.local/share/mise` holds the installed tool binaries (`installs/`) and shims (`shims/`); caching it makes the second run's `mise install` a no-op. (mise's small aqua-registry index lives in its own cache dir and is re-fetched on a cold runner — cheap; the expensive tool binaries come from the cache.)
- Bumping a version in `.mise.toml` changes `hashFiles('.mise.toml')` and forces a fresh install.

### Verification

#### Automated
- [ ] Locally: `mise install` succeeds, then `mise exec -- swiftformat --version` and `mise exec -- swiftlint version` report the pinned versions from `.mise.toml`.
- [ ] Locally: `swiftformat --lint SingleThread/ SingleThreadTests/ SingleThreadUITests/` and `swiftlint lint --strict --config .swiftlint.yml` pass against the pinned tools (with `~/.local/share/mise/shims` on PATH, or via `mise exec --`).

#### Manual
- [ ] CI `lint` job passes end-to-end with the unchanged SwiftFormat/SwiftLint commands.
- [ ] Two consecutive CI runs: the `mise install` step is effectively a no-op on the second run (cache hit on `lint-tools-…`).
- [ ] Bump a version in `.mise.toml` (e.g. `swiftformat` to a newer release) and confirm the `Cache lint tools` step reports a miss and `mise install` downloads the new tool.

---

## Testing Checkpoints (rolled into the phases above)

- **After Phase 1**: `./scripts/test.sh` and `make build && make test` are green and byte-match CI's build/test commands; CI compiles once; `test` job faster than baseline.
- **After Phase 2**: `SingleThreadTests` builds as a non-hosted `.xctest`; 7 tests pass unchanged; no `TEST_HOST`/`BUNDLE_LOADER`/`TestTargetID` on the unit target; project opens in Xcode.
- **After Phase 3**: cache restores `$GITHUB_WORKSPACE/DerivedData`; edits to test sources or `project.pbxproj` invalidate the key (no stale pass); Xcode version bump auto-invalidates.
- **After Phase 4**: lint tools install from cache, pinned by `.mise.toml`; lint job deterministic.
