# Structure Outline

## Approach

Replace the Watch reminder card's long-press options menu with a plain `onTapGesture`
(tap the card → "Refresh" confirmation dialog), backfill accessibility annotations on the
icon-only action buttons to match iOS/macOS, and seed a net-new watch UI test target so the
flow is exercised and CI-guarded rather than compile-only.

> **Scope note.** This change has no data/model/API layer — it lives entirely on the watch UI
> surface plus a brand-new XCTest target. There is no movement in a normal vertical direction
> (db → service → API → UI); instead "vertical" here means the **whole toolchain**: UI source
> → fixed Xcode project target → runnable test → CI wiring. Each phase below crosses that full
> chain in isolation. Note also that the watch UI test infra is genuinely net-new (research Q3)
> — it cannot be pre-sliced into a no-op scaffold without doubling effort, so Phase 3 is a
> single, deliberately sized slice.

---

## Phase 1: Tap-to-reveal the reminder menu

Delivers the core behavior: a plain tap on the reminder card presents the `"Reminder"`
confirmation dialog with the Refresh action, replacing the long-press trigger.

**Files**: `SingleThreadWatch/WatchReminderView.swift`

**Key changes** (in `private func reminderCard(_ reminder: EKReminder) -> some View`):
- `ScrollView { reminderDetails(reminder) }`
  - `.onLongPressGesture { isShowingRefreshConfirmation = true }` →
    `.onTapGesture { isShowingRefreshConfirmation = true }`
  - add `.accessibilityAddTraits(.isButton)` (required by SwiftLint
    `accessibility_trait_for_button`; the ScrollView is the tap target)
- Keep `.confirmationDialog("Reminder", isPresented: $isShowingRefreshConfirmation)`
  and its single `Button("Refresh") { refresh() }` unchanged.
- `@State isShowingRefreshConfirmation: Bool` unchanged.

**Note:** do not convert the dialog's Refresh into a second real `Button`; the whole-card tap
must remain a gesture, not a button, per design decision 1.

**Verify**: `make watch-build` builds; `swiftlint lint --strict` passes with **no**
`accessibility_trait_for_button` warning. Manual: open the "Reminder" `#Preview` in the SwiftUI
canvas, single-tap the card → dialog appears. Confirm the tap region bounds the card HStack
(not the whole window) — `.local` coordinate space; if it proves too eager, fall back to a
smaller tap target per design.md Open Risks.

---

## Phase 2: Backfill Complete/Skip accessibility (iOS/macOS parity)

Delivers the reachability baseline: the two icon-only action buttons are VoiceOver-intelligible.

**Files:** `SingleThreadWatch/WatchReminderView.swift` — `private var actionButtons: some View`

**Key changes** (mirrors `SingleThread/ContentView.swift:202-203` / `:214-215`):
- Complete `Button`: add `.accessibilityLabel("Complete reminder")` +
  `.accessibilityAddTraits(.isButton)`
- Skip `Button`: add `.accessibilityLabel("Skip reminder")` +
  `.accessibilityAddTraits(.isButton)`

**Verify**: `make watch-build` + `swiftlint lint --strict` pass (these are new annotations, so
no new violations — confirms the whole target stays lint-clean). Manual: VoiceOver announces
"Complete reminder" / "Skip reminder" on each button.

> Phases 1–2 both touch `WatchReminderView.swift` and are independently shippable; 1 is the
> demanded behavior, 2 is standalone accessibility debt.

---

## Phase 3: New `SingleThreadWatchUITests` XCTest target

Delivers the never-before-existing watch UI test harness and the interaction-level assertions.

**Files:**
- `SingleThread.xcodeproj/project.pbxproj` — new `SingleThreadWatchUITests` native target
  (mirror `SingleThreadUITests`):
  - `productType = "com.apple.product-type.bundle.ui-testing"`
  - `SDKROOT = watchos`; `SUPPORTED_PLATFORMS = "watchos watchsimulator"`
  - `TEST_TARGET_NAME = SingleThreadWatch`; `TEST_HOST` → watch app built product
  - `PBXTargetDependency` on `SingleThreadWatch` target; new `fileSystemSynchronizedGroups`
    entry for the new source folder
- `SingleThread.xcodeproj/xcshareddata/xcschemes/SingleThreadWatch.xcscheme` — populate the
  currently-empty `TestAction` (`<Testables>` / testableTargetKey) so `test` resolves the
  `SingleThreadWatch` + `SingleThreadWatchUITests` targets.
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift` — XCTestCase for interaction
  + accessibility audit
- `SingleThreadWatchUITests/SingleThreadWatchUITestsLaunchTests.swift` — launch + screenshot

**Key type signatures:**
- `final class SingleThreadWatchUITests: XCTestCase` with
  - `override func testLaunch() throws` (@MainActor) — `XCUIApplication()`,
    `launchArguments = ["--ui-testing"]`, `app.launch()`
  - `func testTapRevealsConfirmationDialog() throws` — single tap on card → assert
    `app.confirmationDialog`-shaped element (Refresh button) exists
  - `func testAccessibilityAudit() throws` — `app.performAccessibilityAudit(...)` where the
    watch simulation supports it
- `final class SingleThreadWatchUITestsLaunchTests: XCTestCase` with
  `override class var runsForEachTargetApplicationUIConfiguration: Bool { true }`

**Verify** (local): `xcodebuild -scheme SingleThreadWatch
-destination 'generic/platform=watchOS Simulator' -derivedDataPath 'DerivedData' test
-only-testing:SingleThreadWatchUITests` passes — the tap-presentation and audit assertions hold.
Adjust tap coordinate space here if Phase 1 exposed a larger-than-intended region.

---

## Phase 4: Wire `watch-ui-test` into Makefile, `scripts/test.sh`, and CI

Delivers the guarding: the new test runs in local full-pipeline runs and in CI, not just
ad hoc.

**Files:**
- `Makefile` — new `watch-ui-test` target (mirror `ui-test`, using `WATCH_SIM` /
  `WATCH_SCHEME` + an `-only-testing:SingleThreadWatchUITests` test invocation)
- `scripts/test.sh` — add a "Watch UI tests…" step after "UI tests" in the full pipeline
  (`MODE = full`), reusing `WATCH_SIM` / clean build config
- `.github/workflows/ci.yml` — add a `watch-ui-tests` job once the `ui-tests` job is available
  ("Pre-boot simulator", build, then `test-without-building -only-testing:SingleThreadWatchUITests`);
  include `SingleThreadWatchUITests/**` in the cache key hash

**Verify**: `make watch-ui-test` passes on its own; full `./scripts/test.sh` runs the new step;
the `watch-ui-tests` CI job passes. Watch build + lint stay green.

---

## Testing Checkpoints

- **After Phase 1:** watch builds; `swiftlint --strict` clean; card tap opens the Refresh
  dialog in the Simulator canvas. (Behavioral fix is in place; no automated test yet.)
- **After Phase 2:** watch still builds + lint-clean; Complete/Skip are announced by
  VoiceOver. (Both chunks of UX complete, still guarded only by build + manual preview.)
- **After Phase 3:** `xcodebuild -scheme SingleThreadWatch ... test
  -only-testing:SingleThreadWatchUITests` passes; tap→dialog and accessibility audit are
  exercised by a runnable watch UI test.
- **After Phase 4:** `make watch-ui-test` and full `./scripts/test.sh` green; CI runs
  `watch-ui-tests`. The whole flow is now CI-guarded. Resume point is safe at any single phase.

**Net-new risk to watch while implementing:** the `SingleThreadWatchUITests` target + scheme
`TestAction` + CI job are all first-contact infra (no watch target depends on them today), and
`.onTapGesture` on a scrollable card may expose a wider hit-region than intended — the
single-tap behavior sample in Phase 1 / Phase 3's tap assertion is where that risk surfaces.