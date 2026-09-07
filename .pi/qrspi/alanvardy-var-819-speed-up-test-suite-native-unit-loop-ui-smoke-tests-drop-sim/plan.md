# Implementation Plan — Speed up the test suite

## Overview

Cut wall-clock time by (1) making the local unit loop run natively on macOS instead of the ~10× slower iOS Simulator, (2) dropping the duplicate iOS-Sim unit pass from the local full gate while keeping it in CI, and (3) collapsing 23 iOS + 15 watch UI methods into one launch-and-render a11y smoke test per platform on an iPhone-only CI matrix — all with the `--seed`/`--ui-testing` seams byte-identical and zero native unit tests removed.

Stages are ordered bottom-up; each ships its code **and** its verification green before the next starts. Stage 4 (CI) has no local runtime gate and is verified by inspection + the PR's CI run.

---

## Stage 1: Smoke-Test Content — the new UI test surface (foundation)

Write the two surviving UI smoke methods before deleting anything. Green here proves a plain `--ui-testing` launch renders the expected card and the minimal a11y audit passes on both platforms.

### Changes

#### 1. iOS smoke method
**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify (replace `testAccessibilityAudit` with `testLaunchAndRenderSmoke`)

Replace the entire file body below the banner comment (`import XCTest` onward). Keep the class name, the `runsForEachTargetApplicationUIConfiguration = false` override, and `setUpWithError`.

```swift
import XCTest

final class SingleThreadUITests: XCTestCase {

    // `class` is required to override XCTestCase's class property; `static` cannot
    // override it. Run once (not once per target app configuration): the smoke
    // launches one deterministic app state; multiplying it by the configuration
    // count adds redundant cold launches on CI for no coverage.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndRenderSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Plain --ui-testing seeds one reminder ("Buy groceries" /
        // "Don't forget the milk", priority 5 → "!!") with
        // enableActionButtons ON, so the card + Complete/Skip/mic cluster render.
        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Reminder title should render")
        XCTAssertTrue(app.staticTexts["Don't forget the milk"].exists,
                      "Reminder notes should render")
        XCTAssertTrue(app.staticTexts["priorityMarker"].exists,
                      "Priority marker \"!!\" should render")
        XCTAssertTrue(app.buttons["completeButton"].exists,
                      "Complete action should render")
        XCTAssertTrue(app.buttons["skipButton"].exists,
                      "Skip action should render")
        XCTAssertTrue(app.buttons["dictateButton"].exists,
                      "Dictate action should render")

        // Fold the CI-parity a11y audit into the smoke check, using the cheap,
        // non-rendering categories only. .dynamicType/.hitRegion can hang on
        // GitHub's virtualized runners and are covered by unit suites
        // (TextSizeTests etc.), so they are deliberately excluded — matching the
        // former CI carve-out, now applied everywhere (local and CI alike).
        try app.performAccessibilityAudit(
            for: [.sufficientElementDescription, .trait]
        )
    }
}
```

#### 2. Watch smoke method
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITests.swift`
**Action**: modify (replace `testAccessibilityAudit` with `testLaunchAndRenderSmoke` + add the private `launchApp()` helper)

```swift
import XCTest

final class SingleThreadWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchAndRenderSmoke() throws {
        let app = launchApp()

        XCTAssertTrue(
            app.staticTexts["Buy groceries"].waitForExistence(timeout: 5),
            "Reminder card should render")
        XCTAssertTrue(app.staticTexts["Don't forget the milk"].exists,
                      "Reminder notes should render")
        XCTAssertTrue(app.staticTexts["priorityMarker"].exists,
                      "Priority marker \"!!\" should render")

        try app.performAccessibilityAudit(
            for: [.sufficientElementDescription, .trait]
        )
    }

    // Relocated verbatim from SingleThreadWatchUITestsFlows.swift:298-304
    // (deleted in Stage 2).
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }
}
```

> **Deviation from design.decision 7**: the design lists `completeButton`/`skipButton` as watch smoke assertions. These are entitlement-gated on watch — `WatchReminderView.swift:270-273` renders `actionButtons` only when `store.canMutate` OR `entitlementState.isEnabled`, and the plain `--ui-testing` watch store (`WatchAppViewModel.recoveryTestingStore`) passes **no** testing entitlement, so button presence depends on real host entitlement resolution (the same host-state flakiness that keeps the existing watch audit test title-only). The watch smoke asserts only the deterministic card (title, notes, priority marker), identical to what the existing green `testAccessibilityAudit` already proves. iOS buttons ARE deterministic (the `--ui-testing` seam forces `enableActionButtons=true` + `EntitlementStore(testingWithEntitled:false)` and the action cluster requires only `canDictate`, which is true wherever the existing Flows tests already tap those buttons).

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.7' -only-testing:SingleThreadUITests/testLaunchAndRenderSmoke` passes
- [x] `xcodebuild test -scheme SingleThreadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -only-testing:SingleThreadWatchUITests/testLaunchAndRenderSmoke` passes
- [x] `make format` produces no diff to these two files (idempotent)
- [x] `make lint` clean

#### Manual
- [ ] Run the iOS smoke and confirm the simulator shows the "Buy groceries" card (title, "!!", notes) and Complete/Skip/mic buttons before the audit runs
- [ ] Run the watch smoke and confirm the watch shows the "Buy groceries" card (title, "!!", notes)

---

## Stage 2: Collapse the Superseded UI Surface

Delete every UI test the smoke tests now cover. Green here proves the collapsed targets still compile, lint, and run exactly one method.

### Changes

#### 1. Delete iOS UI files (9)
**Action**: delete
**Files**:
- `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift`
- `SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests.swift`
- `SingleThreadUITests/SingleThreadUITestsFlows.swift`
- `SingleThreadUITests/ActionButtonsUITests.swift`
- `SingleThreadUITests/NotificationsSettingsUITests.swift`
- `SingleThreadUITests/NotificationsUITests.swift`
- `SingleThreadUITests/SkipNudgeUITests.swift`
- `SingleThreadUITests/ActionMenuUITests.swift` (empty)
- `SingleThreadUITests/NotificationSchedulingUITests.swift` (empty)

#### 2. Delete watch UI files (2)
**Action**: delete
**Files**:
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
- `SingleThreadWatchUITests/SingleThreadWatchUITestsLaunchTests.swift`

#### 3. Keep (do NOT modify)
**Files**:
- `SingleThreadUITests/SingleThreadUITestCase.swift` — shared base (`launchApp`, `launchSeeded`, `flipToggle`, `assertTogglePersists`, `statusLabel`) still serves the survivor class and any future UI tests
- `SingleThreadUITests/SingleThreadUITests.swift` — the Stage 1 smoke (sole iOS method)
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — the Stage 1 smoke (sole watch method)

No pbxproj edits are required: the groups are synchronized (`objectVersion = 77`) and `project.pbxproj` contains **zero** references to any file named above (verified — `grep -c` returned 0).

`runsForEachTargetApplicationUIConfiguration = true` (the lone explicit `true` at the deleted `SingleThreadWatchUITestsLaunchTests.swift:6-7` plus all implicit `true` flow defaults) leaves the repo with those files; the two survivors keep iOS `false` / watch default.

### Verification

#### Automated
- [ ] Same two targeted smoke runs from Stage 1 still pass (now the sole members)
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=18.7' -only-testing:SingleThreadUITests` returns in ~1 method (not 23)
- [ ] `make format` clean
- [ ] `make lint` clean
- [ ] `rm -rf DerivedData` then `make periphery` clean (catches dangling refs to deleted classes)

#### Manual
- [ ] Confirm `SingleThreadUITests` and `SingleThreadWatchUITests` targets each expose exactly one `@MainActor func testLaunchAndRenderSmoke`

---

## Stage 3: Local Runner Reconfiguration — `scripts/test.sh` + `Makefile`

Repoint the local scripts at the native unit loop and delete the duplicate iOS-Sim unit phase from the full pipeline. `Makefile` needs no edit (its `test` target passes `--unit-only`, which now resolves natively).

### Changes

#### 1. `--unit-only` block → native macOS
**File**: `scripts/test.sh`
**Action**: modify (replace the iOS-Sim build-for-testing + test pair with a single native macOS `test` run — the `test` action self-builds, mirroring phase 13 `scripts/test.sh:285-291` and `Makefile:26` `mac-test`)

Find the block beginning `if [[ "${UNIT_ONLY:-0}" -eq 1 ]]; then` and replace its body:

```bash
if [[ "${UNIT_ONLY:-0}" -eq 1 ]]; then
    echo "==> Unit tests (macOS native)…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadTests

    echo ""
    echo "✅ Unit tests passed (macOS native)."
    exit 0
fi
```

(`$MAC_SIM="platform=macOS"` is already set at `:12`; no new variable needed.)

#### 2. Full pipeline → remove the iOS-Sim unit phase
**File**: `scripts/test.sh`
**Action**: modify (delete the phase-7 block between Periphery and iOS UI)

Delete exactly this block (including its leading `echo ""` separator):

```bash
    echo ""
    echo "==> Unit tests…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$SIM" \
      -derivedDataPath "$DERIVED_DATA" \
      -parallel-testing-enabled YES \
      -maximum-test-execution-time-allowance 900 \
      test-without-building \
      -only-testing:SingleThreadTests
```

Resulting full pipeline order: format → fmt-check → swiftlint → iOS build → watch build → periphery → iOS UI → watch build(concrete)+dylib fix → watch UI → watch unit → **macOS unit**. The `-parallel-testing-enabled YES` flag disappears with the block (it was unique to that phase).

Untouched: pre-boot (`:22-48`), runtime cleanup (`:52-83`), deploy-target guard (`:110-192`), iOS build (`:210-216`, stays unfiltered — still compiles the iOS-Sim `SingleThreadTests` bundle for the build, but it is no longer run locally), watch dylib fix (`:256-267`), macOS unit phase (`:285-291`, already last), `--ui-only` (`:322-341`).

#### 3. `Makefile`
**File**: `Makefile`
**Action**: none (textually unchanged). `test` → `--unit-only` (`:78-79`) now resolves to the native run; `ui-test` (`:81-82`) and `check` (`:103-104`) unchanged.

### Verification

#### Automated
- [ ] `./scripts/test.sh --unit-only` runs `SingleThreadTests` natively on `platform=macOS` (watch the `xcodebuild` destination in output — must be `-destination 'platform=macOS'`, not the sim)
- [ ] `make test` passes (same native path; annotate the 3 known pre-existing macOS failures — `EntitlementStoreTests.isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`, `hostStoreKitIsClean` — never debug)
- [ ] Same two targeted smoke runs from Stage 1 still pass (their filters are unused by `--unit-only`; no change)

#### Manual
- [ ] Confirm the full-pipeline phase list (dry-run by reading `scripts/test.sh`) shows the iOS-Sim unit phase gone and macOS unit still last

---

## Stage 4: CI Reconfiguration — `ci.yml`

Point CI at the single smoke method on an iPhone-only matrix and remove the now-dead class references. **No local runtime gate** (CI runs only on push to `main`); semantics are exercised locally by Stage 3 because the same `-only-testing:<method>` name is used. Verification is inspection + the PR's CI run.

### Changes

#### 1. Remove the env-group split
**File**: `.github/workflows/ci.yml`
**Action**: modify (delete the top-level `env:` block `:11-17` and its preceding comment "Single source of truth for the iOS UI class groups…") — after the merge below, no job references `UI_GROUP_*`.

#### 2. Merge the 3 iOS UI jobs → `ui-tests-smoke`
**File**: `.github/workflows/ci.yml`
**Action**: modify (replace `ui-tests-flows` `:93-161`, `ui-tests-launch-appearance` `:163-231`, and `ui-tests-audits` `:233-301` with one job)

```yaml
  ui-tests-smoke:
    runs-on: macos-26
    strategy:
      matrix:
        device: ["iPhone 17"]
    env:
      SIM: platform=iOS Simulator,name=${{ matrix.device }}
      DERIVED_DATA: ${{ github.workspace }}/DerivedData
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        id: xcode
        with:
          xcode-version: '26.6'

      - name: Override development team
        run: echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV

      - uses: actions/cache@v4
        with:
          path: ${{ github.workspace }}/DerivedData
          key: derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadUITests/**', 'SingleThreadCore/**', 'SingleThreadWatch/**', 'SingleThreadWatchUITests/**', 'SingleThreadWidget/**', 'SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-
            derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-

      - name: Pre-boot simulator
        run: |
          SIM_UDID=$(xcrun simctl list devices available | grep -F "${{ matrix.device }} (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')
          xcrun simctl boot "$SIM_UDID" || true
          xcrun simctl bootstatus "$SIM_UDID" -b

      - name: Build
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadUITests \
            -showBuildTimingSummary

      - name: UI tests (smoke)
        timeout-minutes: 45
        run: |
          # One launch-and-render smoke test folding in the minimal a11y audit.
          # Disable parallel test simulator clones: on GitHub's virtualized macOS
          # runners the iOS clone connection to com.apple.instruments.deviceservice
          # .lockdown can time out (120s) and stall the whole step.
          xcodebuild -scheme SingleThread \
            -destination "$SIM" \
            -derivedDataPath "$DERIVED_DATA" \
            -maximum-test-execution-time-allowance 900 \
            -retry-tests-on-failure \
            -parallel-testing-enabled NO \
            -maximum-concurrent-test-simulator-destinations 1 \
            test-without-building \
            -only-testing:SingleThreadUITests/testLaunchAndRenderSmoke
```

#### 3. Watch UI filter → smoke method
**File**: `.github/workflows/ci.yml`
**Action**: modify (change the "Watch UI tests" step `-only-testing:SingleThreadWatchUITests` → `-only-testing:SingleThreadWatchUITests/testLaunchAndRenderSmoke`)

The build-for-testing step keeps its two target filters (`-only-testing:SingleThreadWatchUITests -only-testing:SingleThreadWatchTests`); the watch-unit step (`-only-testing:SingleThreadWatchTests`) is untouched.

#### 4. Untouched jobs (verify only)
- `unit-tests` (`:19-91`) — retains the iOS-Sim unit pass in CI (the retained sim run)
- `mac-tests` (`:303-357`) — retains `CODE_SIGNING_ALLOWED=NO` native pass
- `lint` (`:355-411`) — unchanged

### Verification

#### Automated
- [ ] `npx actionlint` (or `ruby -e "require 'yaml'; YAML.load_file('.github/workflows/ci.yml')"`) parses clean
- [ ] `grep -n "only-testing\|UI_GROUP\|SingleThreadUITests[A-Za-z]*\|SingleThreadWatchUITests[A-Za-z]*" .github/workflows/ci.yml` shows only `SingleThreadUITests/testLaunchAndRenderSmoke` and `SingleThreadWatchUITests/testLaunchAndRenderSmoke` (plus the watch unit target name `SingleThreadWatchTests`), and **no** reference to any deleted class
- [ ] `grep -n "device:" .github/workflows/ci.yml` confirms the UI smoke job matrix is `["iPhone 17"]` and `unit-tests`/`mac-tests`/`lint`/`watch-ui-tests` have no matrix

#### Manual
- [ ] Read the merged job and confirm every `-only-testing` name matches a surviving member from the Stage 2 file list
- [ ] Confirm no `UI_GROUP_*` reference remains anywhere in `ci.yml`

---

## Testing Checkpoints (resume after any context reset)

1. After **Stage 1** — the 2 smoke methods pass their targeted `xcodebuild … -only-testing:…/testLaunchAndRenderSmoke` runs and `make lint` is clean.
2. After **Stage 2** — same 2 smoke runs still green (now sole members), `make lint`/`make format`/`make periphery` (after `DerivedData/` wipe) clean.
3. After **Stage 3** — `make test` runs `SingleThreadTests` **natively** and passes (3 known macOS `EntitlementStoreTests` host-state failures annotated, never debugged).
4. After **Stage 4** — `actionlint` clean and every CI `-only-testing` name matches a surviving member.

## Final integration

Launch the full `./scripts/test.sh` exactly once via the `run-gate` skill — one dedicated async gate subagent in a managed worktree with a multi-hour timeout (never `nohup` it ad-hoc; never re-run it per stage). It must show: the reordered pipeline with the iOS-Sim unit phase gone, the collapsed smoke UI phases passing, and the macOS unit phase (now the sole full-gate unit pass locally) green. After two UI-stage contention failures, stop re-running locally — CI is authoritative.

## PR description note

Add one line calling out the `--unit-only`/`make test` behavior change: devs now get a native macOS pass that excludes the 57 iOS-only tests (`AppDelegateTests`, `BackgroundCardTests`, and the 4 WatchConnectivity sync files), with those remaining CI-only — so the changed local loop doesn't read as a lost regression.