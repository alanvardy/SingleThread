# Implementation Plan

> **Branch** (artifact dir): `alanvardy-var-638-design-change-long-press-to-regular-press-on-apple-watch`

## Overview

Replace the Apple Watch reminder card's long-press options menu with a plain tap on the card
(which reveals the "Reminder" confirmation dialog with its single "Refresh" action), keep that
dialog unchanged, backfill accessibility annotations on the icon-only Complete/Skip action
buttons to match iOS/macOS, and seed a brand-new `SingleThreadWatchUITests` XCTest target so
the tap→dialog flow and the accessibility work are exercised by an interaction-level watch UI
test guarded locally (`make watch-ui-test`, `./scripts/test.sh`) and in CI.

> **Deviation from structure outline (approved option A).** Phase 3 as outlined could not
> produce a testable reminder card: under the harness's prescribed launch
> (`app.launchArguments = ["--ui-testing"]`), `SingleThreadWatchApp.swift` sets
> `loadsReminders: false`, `ReminderStore.start()` early-returns, `authorizationStatus` stays
> `.notDetermined`, and the view renders only `ProgressView("Requesting access…")` — no card,
> no tap target, no Complete/Skip buttons. So `testTapReveals…Dialog` and
> `testAccessibilityAudit` would have nothing to exercise. The fix is a **test seam** (added to
> `SingleThreadWatchApp.swift`): when `--ui-testing` is present, seed the store via the
> existing preview-style initializer with one mock reminder and `.fullAccess`, so a real
> reminder card presents deterministically. All other phases are as outlined.

---

## Phase 1: Tap-to-reveal the reminder menu

Replace the card's `.onLongPressGesture` with `.onTapGesture` and mark the tap target as a
button (SwiftLint `accessibility_trait_for_button`). Keep the confirmation dialog and its
Refresh action unchanged.

### Changes

#### 1. `SingleThreadWatch/WatchReminderView.swift` — `reminderCard(_ reminder:)`

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

The card's `ScrollView` currently is (inside `reminderCard`, `:129-139`):

```swift
ScrollView {
    reminderDetails(reminder)
}
.onLongPressGesture {
    isShowingRefreshConfirmation = true
}
.confirmationDialog("Reminder", isPresented: $isShowingRefreshConfirmation) {
    Button("Refresh") { refresh() }
}
```

Change to:

```swift
ScrollView {
    reminderDetails(reminder)
}
.onTapGesture {
    isShowingRefreshConfirmation = true
}
.accessibilityAddTraits(.isButton)
.confirmationDialog("Reminder", isPresented: $isShowingRefreshConfirmation) {
    Button("Refresh") { refresh() }
}
```

- Keep `@State private var isShowingRefreshConfirmation = false` and the dialog's single
  `Button("Refresh")` **unchanged** (Design Decision 2; the whole-card gesture must remain a
  gesture, not a real button).
- Do **not** convert the dialog's Refresh into a second real `Button`, and do not widen the
  menu (single action only).

### Verification

#### Automated
- [x] `make watch-build` succeeds.
- [x] `make lint` passes — specifically no `accessibility_trait_for_button` warning from
  `WatchReminderView.swift` (the new `.onTapGesture` + `.accessibilityAddTraits(.isButton)`
  pair satisfies the rule).
- [x] `swiftlint lint --strict` (from repo root) emits no new violations in
  `SingleThreadWatch/`.

#### Manual
- [ ] Open the "Reminder" `#Preview` in the SwiftUI Simulator canvas; single-tap the reminder
      card → the "Reminder" confirmation dialog with a "Refresh" button appears.
- [ ] Confirm the card tap region bounds the card `ScrollView`/`VStack` (`.local` coordinate
      space), **not** the whole window. If tap reveals gap from tapping outside the card, fall
      back to a smaller inner tap target (see Design Open Risks).

---

## Phase 2: Backfill Complete/Skip accessibility (iOS/macOS parity)

Add `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)` to the two icon-only action
buttons so VoiceOver announces them, mirroring `SingleThread/ContentView.swift:202-203` /
`:214-215`.

### Changes

#### 1. `SingleThreadWatch/WatchReminderView.swift` — `actionButtons`

**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Current `actionButtons` (`:83-101`) has two icon-only `Button`s. Change each to add the two
annotations after `.tint(...)`, keeping the icon, `labelStyle(.iconOnly)`, and tint unchanged:

```swift
private var actionButtons: some View {
    HStack {
        Button {
            Task { await store.completeCurrentReminder() }
        } label: {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
        }
        .tint(.green)
        .accessibilityLabel("Complete reminder")
        .accessibilityAddTraits(.isButton)

        Button {
            store.skipCurrentReminder()
        } label: {
            Label("Skip", systemImage: "circle.slash")
                .labelStyle(.iconOnly)
        }
        .tint(.orange)
        .accessibilityLabel("Skip reminder")
        .accessibilityAddTraits(.isButton)
    }
}
```

### Verification

#### Automated
- [x] `make watch-build` succeeds.
- [x] `swiftlint lint --strict` passes with no new violations (additive annotations only;
      target stays lint-clean).
- [x] `./scripts/test.sh --unit-only` still passes (no core/model change, but confirms the
      package link is intact).

#### Manual
- [ ] In the Simulator canvas "Reminder" `#Preview`, VoiceOver announces "Complete reminder"
      and "Skip reminder" on the two icon-only action buttons.

---

## Phase 3: New `SingleThreadWatchUITests` XCTest target

Seed the never-before-existing watch UI test harness and the interaction-level assertions,
plus the **test seam** (option A) that makes a reminder card presentable under the harness.

### Changes

#### 1. `SingleThreadWatch/SingleThreadWatchApp.swift` — test seam (option A)

**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

Add `import EventKit`. Rework `init()` so `--ui-testing` seeds a deterministic reminder card
instead of requesting real reminder access:

```swift
import SingleThreadCore
import EventKit
import SwiftUI
import WatchConnectivity

@main
struct SingleThreadWatchApp: App {
    // MARK: Lifecycle
    init() {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let store: ReminderStore
        if isUITesting {
            store = uiTestingStore()
        } else {
            store = ReminderStore(loadsReminders: true)
        }
        self.store = store
        // ...rest of init unchanged (sort restore, WCSession wiring)...
    }
    // ...
    // MARK: Private

    private func uiTestingStore() -> ReminderStore {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        reminder.notes = "Don't forget the milk"
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }
}
```

This reuses the existing preview initializer `ReminderStore(loadsReminders:, reminders:,
skippedIDs:, authorizationStatus:)` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:26-35`),
so the view's `body` switch (`WatchReminderView.swift:28-37`) hits `case .fullAccess` →
`reminderContent` → `reminderCard`, and `visibleReminders.first` is non-nil (empty `skippedIDs`),
so the card (with the `.onTapGesture` target, Complete and Skip icons) renders. No real EventKit
I/O occurs (`loadsReminders: false` short-circuits `start()`). `EKEventStore`/`EKReminder`
already compile into the watch target via the `mockWatchReminder` fixture
(`WatchReminderView.swift:204-212`).

> **Codegen fallback.** If the synchronized-folder system doesn't auto-pick up new `.swift`
> files, register the folder in the target's `fileSystemSynchronizedGroups` within
> `project.pbxproj` (next change). The seam itself is a plain edit; no other codegen step.

#### 2. `SingleThread.xcodeproj/project.pbxproj` — new `SingleThreadWatchUITests` target

**File**: `SingleThread.xcodeproj/project.pbxproj`
**Action**: modify (add `PBXNativeTarget` + supporting objects)

Mirror the existing `SingleThreadUITests` native target (`:244-279`) but with watchOS settings.
Allocate these **new, currently-unused** 24-hex object IDs (do not collide with any existing id):

| Role | ID |
|---|---|
| native target | `51AA3F600000000000000001` |
| product `.xctest` file | `51AA3F610000000000000002` |
| sync root group | `51AA3F620000000000000003` |
| config list | `51AA3F630000000000000004` |
| Debug config | `51AA3F640000000000000005` |
| Release config | `51AA3F650000000000000006` |
| Sources phase | `51AA3F660000000000000007` |
| Frameworks phase | `51AA3F670000000000000008` |
| Resources phase | `51AA3F680000000000000009` |
| container item proxy | `51AA3F69000000000000000A` |
| target dependency | `51AA3F6A000000000000000B` |

Required additions, by section (exact pbxproj text):

**PBXFileReference** (with the other `wrapper.cfbundle` products, near `:77`):
```
51AA3F610000000000000002 /* SingleThreadWatchUITests.xctest */
  = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0;
     path = SingleThreadWatchUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

**PBXFileSystemSynchronizedRootGroup** (near `:108`):
```
51AA3F620000000000000003 /* SingleThreadWatchUITests */
  = {isa = PBXFileSystemSynchronizedRootGroup; path = SingleThreadWatchUITests;
     sourceTree = "<group>"; };
```

**Sources / Frameworks / Resources build phases** — three phase objects
(`51AA3F660000000000000007`, `51AA3F670000000000000008`, `51AA3F680000000000000009`) with
empty `files = ( );`, mirroring the `SingleThreadUITests` phases.

**PBXGroup** — add the new folder + product to the canvas:
- Root children group: add `51AA3F620000000000000003 /* SingleThreadWatchUITests */`.
- `Products` group: add `51AA3F610000000000000002 /* SingleThreadWatchUITests.xctest */`.

**PBXNativeTarget** (near `:244`):
```
51AA3F600000000000000001 /* SingleThreadWatchUITests */ = {
    isa = PBXNativeTarget;
    buildConfigurationList = 51AA3F630000000000000004 /* Build configuration list for PBXNativeTarget "SingleThreadWatchUITests" */;
    buildPhases = (
        51AA3F660000000000000007 /* Sources */,
        51AA3F670000000000000008 /* Frameworks */,
        51AA3F680000000000000009 /* Resources */,
    );
    buildRules = ( );
    dependencies = (
        51AA3F6A000000000000000B /* PBXTargetDependency */,
    );
    fileSystemSynchronizedGroups = (
        51AA3F620000000000000003 /* SingleThreadWatchUITests */,
    );
    name = SingleThreadWatchUITests;
    packageProductDependencies = ( );
    productName = SingleThreadWatchUITests;
    productReference = 51AA3F610000000000000002 /* SingleThreadWatchUITests.xctest */;
    productType = "com.apple.product-type.bundle.ui-testing";
};
```

**PBXContainerItemProxy** (near `:19`) + **PBXTargetDependency** (model on the watch's own at
`:456-459`):
```
51AA3F69000000000000000A /* PBXContainerItemProxy */ = {
    isa = PBXContainerItemProxy;
    containerPortal = 51AA3ECE302D5C4500960DFC /* Project object */;
    proxyType = 1;
    remoteGlobalIDString = 51AA3F220000000000000003;
    remoteInfo = SingleThreadWatch;
};
51AA3F6A000000000000000B /* PBXTargetDependency */ = {
    isa = PBXTargetDependency;
    target = 51AA3F220000000000000003 /* SingleThreadWatch */;
    targetProxy = 51AA3F69000000000000000A /* PBXContainerItemProxy */;
};
```

**XCConfigurationList** (near `:952`) for the new target, with Debug + Release + a default,
plus **two `XCBuildConfiguration` entries** allowing the test bundle, mirroring the watch
Debug/Release at `:958-839` but with these buildSettings:

```text
BUNDLE_LOADER            = "$(TEST_HOST)";
CODE_SIGN_STYLE          = Automatic;
CURRENT_PROJECT_VERSION  = 1;
DEVELOPMENT_TEAM         = 6NWX2DHB9Q;
GENERATE_INFOPLIST_FILE  = YES;
MARKETING_VERSION        = 1.0;
PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThreadWatchUITests;
PRODUCT_NAME             = "$(TARGET_NAME)";
SDKROOT                  = watchos;
STRING_CATALOG_GENERATE_SYMBOLS = NO;
SUPPORTED_PLATFORMS      = "watchos watchsimulator";
SWIFT_APPROACHABLE_CONCURRENCY = YES;
SWIFT_DEFAULT_ACTOR_ISOLATION  = MainActor;   // watch app default
SWIFT_EMIT_LOC_STRINGS    = NO;
SWIFT_VERSION             = 6.0;
TARGETED_DEVICE_FAMILY    = 4;
TEST_HOST =
  "$(BUILT_PRODUCTS_DIR)/SingleThreadWatch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SingleThreadWatch";
TEST_TARGET_NAME          = SingleThreadWatch;
WATCHOS_DEPLOYMENT_TARGET = 26.5;
```

> `TEST_HOST` mirrors the iOS `SingleThreadUITests` practice but points at the watch product.
> The pbxproj `objectVersion` sync-group auto-covers the new folder. There is **no** schema
> tied to this step, so no test assertion needs a schema-version bump.

#### 3. `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch.xcscheme` — populate the empty `TestAction`

**File**: `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch.xcscheme`
**Action**: modify

The current `TestAction` (`buildConfiguration = "Debug"`) has no testables. Add them:

```xml
<TestAction
   buildConfiguration = "Debug"
   selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
   selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
   shouldUseLaunchSchemeArgsEnv = "YES"
   shouldAutocreateTestPlan = "YES">
   <Testables>
      <TestableReference
         skipped = "NO"
         parallelizable = "YES">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "51AA3F600000000000000001"
            BuildableName = "SingleThreadWatchUITests.xctest"
            BlueprintName = "SingleThreadWatchUITests"
            ReferencedContainer = "container:SingleThread.xcodeproj">
         </BuildableReference>
      </TestableReference>
   </Testables>
</TestAction>
```

(`BlueprintIdentifier` must equal the pbxproj native-target object ID — same convention as the
existing `SingleThread.xcscheme` testables.)

#### 4. `SingleThreadWatchUITests/` — new XCTest source files

**Files** (create both in the new synchronized folder):
- `SingleThreadWatchUITests.swift`
- `SingleThreadWatchUITestsLaunchTests.swift`

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITests.swift`
**Action**: create

```swift
import XCTest

final class SingleThreadWatchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapRevealsConfirmationDialog() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // The --ui-testing seam seeds a mock "Buy groceries" reminder, so the
        // reminder card (with the onTapGesture target) is presented.
        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Reminder card should be displayed")
        title.tap()

        let refresh = app.buttons["Refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5),
            "Tapping the card should present the Refresh confirmation dialog")
    }

    @MainActor
    func testAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let title = app.staticTexts["Buy groceries"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Reminder card should be displayed")

        #if os(watchOS)
            try app.performAccessibilityAudit(
                for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])
        #endif
    }
}
```

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsLaunchTests.swift`
**Action**: create

```swift
import XCTest

final class SingleThreadWatchUITestsLaunchTests: XCTestCase {
    // `class` is required to override XCTestCase's class property; `static` cannot override it.
    // swiftlint:disable:next static_over_final_class
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Watch Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

Notes:
- `SingleThreadUITests/SingleThreadUITestsLaunchTests.swift` is the launch-screenshot template
  source; `SingleThreadUITests/SingleThreadUITests.swift` is the `tap` /
  `accessibilityAudit` template.
- These files live in `SingleThreadWatchUITests/`, auto-discovered via Xcode's synchronized
  file groups (no per-file pbxproj source edit needed — only the sync-group registration in
  Change 2).

### Verification

#### Automated
- [x] Local build + run of the watch test target:
      ```
      xcodebuild -scheme SingleThreadWatch \
        -destination 'platform=watchOS Simulator,id=<watch simulator device id>' \
        -derivedDataPath 'DerivedData' \
        test \
        -only-testing:SingleThreadWatchUITests
      ```
      passes — tap reveals the Refresh dialog and the accessibility-audit assertion holds.
- [x] `xcodebuild -scheme SingleThreadWatch -destination 'generic/platform=watchOS
      Simulator' -configuration Debug -derivedDataPath 'DerivedData' build` still builds.
- [ ] If the tap region proves wider than the card, adjust the tap target in Phase 1, not the
      test assertion.

#### Manual
- [ ] Inspect `SingleThreadWatchUITests.xcresult` / the launch screenshot — the card
      ("Buy groceries") is foreground with Complete/Skip action buttons visible.
- [ ] The accessibility audit does not report a `trait` violation on the tap
      card (it is `.isButton`) or missing labels on Complete/Skip.

---

## Phase 4: Wire `watch-ui-test` into Makefile, scripts/test.sh, and CI

Make the new test run in local full-pipeline runs and CI, and lint/format the new test sources.

### Changes

#### 1. `Makefile`

**File**: `Makefile`
**Action**: modify

Add `watch-ui-test` to `.PHONY` and add a target mirroring `ui-test`'s test invocation (uses
`WATCH_SIM` + watch scheme + `-only-testing:SingleThreadWatchUITests`):

```make
watch-ui-test:
	xcodebuild -scheme SingleThreadWatch \
	  -destination '$(WATCH_SIM)' \
	  -configuration Debug \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  test \
	  -only-testing:SingleThreadWatchUITests
```

Add `SingleThreadWatchUITests/` to the `lint` and `format` directory lists (with
`SingleThreadUITests/`).

#### 2. `Scripts/test.sh` — add a "Watch UI tests" step

**File**: `scripts/test.sh`
**Action**: modify

In the full pipeline, after the existing "==> UI tests…" step, add:

```bash
echo ""
echo "==> Watch UI tests…"
xcodebuild -scheme "$WATCH_SCHEME" \
  -destination "$WATCH_SIM" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build-for-testing \
  -only-testing:SingleThreadWatchUITests

xcodebuild -scheme "$WATCH_SCHEME" \
  -destination "$WATCH_SIM" \
  -derivedDataPath "$DERIVED_DATA" \
  test-without-building \
  -only-testing:SingleThreadWatchUITests
```

(Reuses `$WATCH_SIM` / `$WATCH_SCHEME` / clean build config. The full pipeline already has a
"Watch build…" step; the new step builds the test bundle for the new target and runs it,
mirroring how the iOS UI tests are built then run.)

Also add `SingleThreadWatchUITests/` to the `swiftformat` / `swiftformat --lint` /
`swiftlint` directory lists (near lines 73-83), and add it to the `included` list in
`.swiftlint.yml`:

```yaml
included:
  - SingleThread
  - SingleThreadCore
  - SingleThreadWatch
  - SingleThreadWidget
  - SingleThreadTests
  - SingleThreadUITests
  - SingleThreadWatchUITests   # new
```

#### 3. `.github/workflows/ci.yml` — add a `watch-ui-tests` job

**File**: `.github/workflows/ci.yml`
**Action**: modify

Add a `watch-ui-tests` job (no device matrix; a single watch simulator), built for the watch
scheme, then run via `test-without-building`. Add `SingleThreadWatchUITests/**` to the
cache-key `hashFiles(...)` globs (the new job's key plus the `lint` job's existing
`derived-data-...` key).

```yaml
  watch-ui-tests:
    runs-on: macos-26
    env:
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
          key: watch-ui-derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThreadWatch/**','SingleThreadWatchUITests/**','SingleThreadCore/**','SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            watch-ui-derived-data-${{ runner.os }}-${{ steps.xcode.outputs.version }}-

      - name: Build watch app + tests
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThreadWatch \
            -destination "generic/platform=watchOS Simulator" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            build-for-testing \
            -only-testing:SingleThreadWatchUITests \
            -showBuildTimingSummary

      - name: Watch UI tests
        timeout-minutes: 20
        run: |
          xcodebuild -scheme SingleThreadWatch \
            -destination "generic/platform=watchOS Simulator" \
            -derivedDataPath "$DERIVED_DATA" \
            test-without-building \
            -only-testing:SingleThreadWatchUITests
```

### Verification

#### Automated
- [x] `make watch-ui-test` passes standalone.
- [x] Full `./scripts/test.sh` runs the new "Watch UI tests…" step; all prior steps still pass
      (format, lint, iOS build, watch build, periphery, unit, UI, macOS).
- [x] `swiftlint --strict` and `swiftformat --lint` cover `SingleThreadWatchUITests/` and pass.
- [x] Re-run the CI `watch-ui-tests` job body locally (confirm a concrete watchOS
      Simulator destination is bootable).

#### Manual
- [ ] CI job list shows a `watch-ui-tests` job alongside `ui-tests` and `unit-tests`.

---

## Testing Checkpoints (single resume point after any phase)

- **After Phase 1**: Watch builds; `swiftlint --strict` clean; the card tap opens the Refresh
  dialog in the Simulator canvas. (Behavioral fix in place; guarded by build + manual preview.)
- **After Phase 2**: Watch still builds + lint-clean; "Complete reminder" / "Skip reminder"
  announced by VoiceOver.
- **After Phase 3**: `xcodebuild -scheme SingleThreadWatch ... test
  -only-testing:SingleThreadWatchUITests` passes; tap→dialog + accessibility audit exercised.
- **After Phase 4**: `make watch-ui-test` and full `./scripts/test.sh` green; CI runs
  `watch-ui-tests`. The whole flow is CI-guarded.

## Known hazards to watch during implementation

- **`.onTapGesture` hit region** may exceed the card (`.local` coordinate space). If Phase 3's
  tap test exposes accidental reveals, tighten the tap target in Phase 1 (a smaller inner
  region) rather than editing test assertions.
- **First-contact watch-test infra**: the new target + `TESTAction` + CI job + `TEST_HOST` are
  all net-new. If `SingleThreadWatch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)` isn't where the watch
  binary lands, resolve the correct `TEST_HOST` (the pattern mirrors iOS but the
  executable path may differ for watchOS).
- **No schema/migration**: no data schema, so no schema-version test updates. The only
  generated artifact is `project.pbxproj` (hand-edited per Phase 3 Change 2) — if `xcodebuild`
  rejects it, reopen in Xcode to regenerate the sync group + scheme rather than fighting the
  pbxproj text.

_End of plan._