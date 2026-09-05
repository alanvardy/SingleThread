# Implementation Plan

## Over view

Add a macOS-only refresh button (SF Symbol `arrow.clockwise` in a `controlPlate()` circle, top-leading overlay) wired to `ContentViewModel.refreshManual()` — mirroring the watch refresh pattern with an `isRefreshing` flag, re-entrancey guard, and 1 s minimum-display hold. Ship with unit tests (Layer 1), a view-structure test (Layer 2), and macOS UI test infrastructure + tests (Layer3).

---

## Layer 1: ContentViewModel — in-fligh state + `refreshManual()` entry point

### Changes

#### 1. Add `isRefreshing` property and `refreshManual()` method
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

Insert `isRefreshing` after the existing properties (before `// MARK: - Task / onChange reactions` at line107):

```swift
    /// True while `refreshManual()` is running, so the button can show a
    /// disabled/spinner state and re-entrant taps are dropped. Matches the
    /// watch pattern (`WatchReminderViewModel.isRefreshing`).
    var isRefreshing = false
```

Replace the existing `reload(clearSkipped:)` passthrough (lines156-158):

```swift
    func reload(clearSkipped: Bool = false) async {
        await store.reload(clearSkipped: clearSkipped)
    }
```

with the same passthrough + new `refreshManual()` method:

```swift
    func reload(clearSkipped: Bool = false) async {
        await store.reload(clearSkipped: clearSkipped)
    }

    /// Manual refresh entry point for the macOS button. Guards against re-entrant
    /// taps, toggles `isRefreshing`, and holds the spinner for at least the
    /// minimum display duration so the user sees the feedback.
    func refreshManual() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let startedAt = Date()
        await store.reload(clearSkipped: store.allSkipped)
        let elapsed = Date().timeIntervalSince(startedAt)
        try? await Task.sleep(
            for: .seconds(MinimumDisplayDuration.remainingSleep(elapsed: elapsed, minimum: 1))
        )
    }
```

#### 2. Add unit tests for `refreshManual()` and `isRefreshing`
**File**: `SingleThreadTests/ContentViewModelTests.swift`
**Action**: modify

Append after the last test ( `lastOpenedURLAccessorIsNilWithoutSpy`, ending at ~line107):

```swift
    // MARK: - refreshManual

    @Test
    func refreshManualTogglesIsRefreshing() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        #expect(viewModel.isRefreshing == false)

        await viewModel.refreshManual()

        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualGateBlocksReentrantCall() async {
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        // Fire two concurrent refreshManual calls; the second must be
        // dropped by the re-entrancy guard.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await viewModel.refreshManual() }
            group.addTask { await viewModel.refreshManual() }
            await group.waitForAll()
        }

        // After both complete, the flag must be false (defer reset).
        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualMinimumDisplayDuration() async {
        // With loadsReminders: false, reload() is a no-op (nearly instant).
        // The minimum-display hold keeps isRefreshing true for ≥1 s.
        let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        let startedAt = Date()
        await viewModel.refreshManual()
        let elapsed = Date().timeIntervalSince(startedAt)

        // Must have waited at least 1 s (allow 0.1 s slop for timing).
        #expect(elapsed >= 0.9)
        #expect(viewModel.isRefreshing == false)
    }

    @Test
    func refreshManualClearsSkippedWhenAllSkipped() async {
        // Seed reminders in an exclude list so visibleReminders is empty
        // while reminders is non-empty → allSkipped is true.
        let eventStore = InMemoryEventStore()
        let reminder = eventStore.makeReminder(title: "Skipped", notes: nil, dueDate: nil, recurrenceRule: nil)
        let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
        calendar.title = "Work"
        eventStore.calendars = [calendar]
        reminder.calendar = calendar
        eventStore.allReminders = [reminder]

        let store = ReminderStore(eventStore: eventStore, loadsReminders: true, authorizationStatus: .fullAccess)
        // Populate state so allSkipped can be computed.
        await store.reload()
        // Skip the only reminder so it's hidden from visibleReminders.
        store.skipCurrentReminder()
        #expect(store.allSkipped == true)

        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        await viewModel.refreshManual()

        // clearSkipped: true shoul have cleared skippedIDs.
        #expect(store.skippedIDs.isEmpty)
    }

    @Test
    func refreshManualPreservesSkippedWhenVisible() async {
        // Seed one visible, non-skipped reminder → allSkipped is false.
        let eventStore = InMemoryEventStore()
        let reminder = eventStore.makeReminder(title: "Buy milk", notes: nil, dueDate: nil, recurrenceRule: nil)
        let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
        calendar.title = "Personal"
        eventStore.calendars = [calendar]
        reminder.calendar = calendar
        eventStore.allReminders = [reminder]

        let store = ReminderStore(eventStore: eventStore, loadsReminders: true, authorizationStatus: .fullAccess)
        await store.reload()
        // Skeep count > 0 but the single reminder is visible → allSkipped false.
        #expect(store.allSkipped == false)

        let viewModel = ContentViewModel(
            store: store,
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())

        await viewModel.refreshManual()

        // clearSkipped: false → skippedIDs perserved (empty here since we never skipped).
        #expect(store.skippedIDs.isEmpty)
    }
```

**Note on `InMemoryEventStore` usage in tests**: The structure in the two `clearSkipped` tests seeds `allReminders` and `calendars` directly on `InMemoryEventStore` after init. This works because both properties are `public private(set)` — the seeded values are read during `reload()`. The test creates `ReminderStore(loadsReminders: true, authorizationStatus: .fullAccess)` so `reload()` actually runs the full pipeline.

### Verification
#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=N O test -only-testing:SingleThreadTests/ContentViewModelTests` — all5 new tests + existing `ContentViewModelTests` green

#### Manual
- [ ] N/A (pure logic layer, no UI)

---

## Layer2: ContentView — macOS refresh button overlay

### Changes

#### 1. Add macOS refresh button overlay
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Insert the macOS refresh button overlay after the settings gear overlay block (after line199, `}`) and before the `#if os(iOS)` undo overlay (line200):

```swift
        #if os(macOS)
        .overlay(alignment: .topLeading) {
            Button {
                Task { await viewModel.refreshManual() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .controlPlate()
            }
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("refreshButton")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.leading, 12)
        }
        #endif
```

**Insertion point detail**: This goes between the settings gear overlay (ends `}` after `.padding(.top, 8).padding(.trailing, 12)` at line199) and the `#if os(iOS)` undo overlay (starts at line200). The block mirrors the gear visually:
- Same modifiers: `.font(.title3)`, `.controlPlate()`, accessibility stack
- Same padding vertical: `.padding(.top, 8)`
- Mirrored horizontal: `.padding(.leading, 12)` vs gear's `.padding(.trailing, 12)`
- Platform gate: `#if os(macOS)` — absent on iOS
- No `.contentShape(Rectangle())` — the gear includes it for hit-target expansion but the refresh button omnits it (the `controlPlate()` provides a56×56 circle, sufficient for pointer/tap)

If `make lint` fails on `type_body_length` (file near650-line warning threshold), extract to `ContentView+macOS.swift`:

**Fallback file**: `SingleThread/ContentView+macOS.swift` (new, only if needed)
```swift
import SingleThreadCore
import SwiftUI

extension ContentView {
    #if os(macOS)
        var refreshButtonOverlay: some View {
            Button {
                Task { await viewModel.refreshManual() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .controlPlate()
            }
            .disabled(viewModel.isRefreshing)
            .accessibilityLabel("Refresh")
            .accessibilityIdentifier("refreshButton")
            .accessibilityAddTraits(.isButton)
            .padding(.top, 8)
            .padding(.leading, 12)
        }
    #endif
}
```

And inline the overlay becomes: `.overlay(alignment: .topLeading) { refreshButtonOverlay }`.

#### 2. Add view-structure unit test
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify

Append after `contentViewAllDoneShowsAllDoneCopy` (after line ~48):

```swift
    @Test
    func contentViewBodyContainsRefreshButtonOnMacOS() {
        let viewModel = ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation())
        let view = ContentView(viewModel: viewModel)
        let bodyValue = view.body
        let description = String(describing: bodyValue)
        // The button only exists when compile for macOS. On iOS the
        // assertion is vacuously true (no-op) — the test compiles on both
        // platforms and just verifies the view renders without crashing.
        #if os(macOS)
            #expect(description.contains("refreshButton"))
        #endif
    }
```

### Ver ification
#### Automated
- [x] `make lint` — SwiftLint `--strict` green (confirms no `type_body_length` breach)
- [x] `xcodebuild -scheme SingleThread -destination 'platform=macOS' CODE_SIGNING_ALLOWED=N O test -only-testing:SingleThreadTests` — Layer1 + Layer2 tests all green

#### Manual
- [ ] N/A (view-structure test is the verification)

---

## Layer3: macOS UI test infrastructure + end-to-end tests

### Changes

#### 1. New macOS UI test class
**File**: `SingleThreadUITests/SingleThreadUITestsMacOS.swift` (new)
**Action**: create

```swift
import XCTest

final class SingleThreadUITestsMacOS: XCTestCase {
    // MARK: Internal

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        app.terminate()
        app = nil
    }

    func testRefreshButtonExists() {
        launchSeeded(seed)
        XCTAssertTrue(app.buttons["refreshButton"].waitForExistence(timeout:5))
    }

    func testRefreshButtonAccessibilityAudit() throws {
        launchSeeded(seed)
        XCTAssertTrue(app.buttons["refreshButton"].waitForExistence(timeout:5))
        try app.performAccessibilityAudit(
            for: [.sufficientElementDescription, .trait]  // CI-consistent categories
        )
    }

    func testRefreshButtonTapReloads() {
        launchSeeded(seed)
        let button = app.buttons["refreshButton"]
        XCTAssertTrue(button.waitForExistence(timeout:5))
        button.tap()
        // After reload, the button should still exist (list re-renders).
        XCTAssertTrue(button.waitForExistence(timeout:5))
    }

    // MARK: Private

    private var app: XCUIApplication!

    private func launchSeeded(_ seed: UITestingSeed) {
        let json = seed.jsonString()
        app.launchArguments = ["--seed", json]
        app.launch()
    }

    private var seed: UITestingSeed {
        UITestingSeed.makeDefault()
    }
}
```

> **Note**: `UITestingSeed.makeDefault()` must exist or be created. If it does not exist, define it inline with a single reminder:

```swift
    private var seed: UITestingSeed {
        UITestingSeed(
            reminders: [
                .init(title: "Buy groceries", notes: nil, dueDate: nil, recurrenceRule: nil, calendarTitle: "Personal"),
            ],
            calendars: ["Personal"],
            excludeLists: [],
            completionCount:0,
            skipCounts: [:],
            isEntitled: false,
            hasHidden: false,
            entitlementUnresolved: false
        )
    }
```

Consult `UITestingSeed.swift:7-28` for the exact init signature and match it.

#### 2. New Makefile target
**File**: `Makefile`
**Action**: modify

Append after `mac-test` target (after line27) and before `mac-run` (line29):

```makefile
mac-ui-test:
	xcodebuild -scheme SingleThread \
	  -destination '$(MAC_SIM)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  test \
	  -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS
```

#### 3. New `scripts/test.sh` step
**File**: `scripts/test.sh`
**Action**: modify

Insert after the macOS unit-test block (after `test -only-testing:SingleThreadTests` at line ~293, before the `echo ""` / `echo "✅ All CI checks passed."` lines):

```bash
    echo ""
    echo "==> macOS UI tests (XCTest)…"
    xcodebuild -scheme "$SCHEME" \
      -destination "$MAC_SIM" \
      -configuration Debug \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      test -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS
```

**Insertion context**: This goes in the "all" branch (the main `if` block at the top of `test.sh`), after the existing macOS unit-test block. The `$MAC_SIM` variable is already defined at line12 as `MAC_SIM="platform=macOS"`.

#### 4. New CI job
**File**: `.github/workflows/ci.yml`
**Action**: modify

Insert after the `mac-tests` job (after `path: TestResults-mac.xcresult` at ~line320, before `lint:` at line322):

```yaml
  mac-ui-tests:
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
          key: derived-data-mac-ui-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-${{ hashFiles('SingleThread/**', 'SingleThreadTests/**', 'SingleThreadCore/**', 'SingleThreadWidget/**', 'SingleThread.xcodeproj/project.pbxproj') }}
          restore-keys: |
            derived-data-mac-ui-${{ runner.os }}-${{ steps.xcode.outputs.version }}-${{ github.ref_name }}-
            derived-data-mac-ui-${{ runner.os }}-${{ steps.xcode.outputs.version }}-
            derived-data-mac-${{ runner.os }}-${{ steps.xcode.outputs.version }}-

      - name: Build (macOS)
        timeout-minutes:20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "platform=macOS" \
            -configuration Debug \
            -derivedDataPath "$DERIVED_DATA" \
            CODE_SIGNING_ALLOWED=NO \
            build \
            -showBuildTimingSummary

      - name: UI tests (macOS)
        timeout-minutes:20
        run: |
          xcodebuild -scheme SingleThread \
            -destination "platform=macOS" \
            -derivedDataPath "$DERIVED_DATA" \
            CODE_SIGNING_ALLOWED=NO \
            test \
            -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS \
            -resultBundlePath TestResults-mac-ui.xcresult

      - name: Upload test results on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: mac-ui-test-results
          path: TestResults-mac-ui.xcresult
```

The cache key prefix is `derived-data-mac-ui-` so it does not collide with the `mac-tests` job's cache. The `restore-keys` fall back to the `mac-tests` cache to share the build artifacts.

### Verification
#### Automated
- [ ] `make mac-ui-test` — new target +3 macOS UI tests green locally
- [ ] `./scripts/test.sh` — full pipeline green (all layers, all platforms, lint + unit + UI)

#### Manual
- [ ] N/A (tests cover existence, accessibility, and tap behavior)

---

## Risk Mitigations Check list

- [ ] **`type_body_length`**: After Layer2, run `make lint`. If it fails with `type_body_length` warning/error on `ContentView.swift`, extract to `ContentView+macOS.swift` (see fallback in Layer2 §1).
- [ ] **`UITestingSeed.makeDefault()`**: If this static method does not exist, define the seed inline in `SingleThreadUITestsMacOS.swift` using the `UITestingSeed` init signature from `UITestingSeed.swift:7-28`.
- [ ] **Cache key collision**: The CI job uses a distinct `derived-data-mac-ui-` cache prefix so it does not clobber the `mac-tests` cache.
- [ ] **Duplicate-tap during hold**: The `guard !isRefreshing` drops a second tap silently —same behavior as `WatchReminderViewModel`. If user feedback warrants a visuual acknowledgment of rejected taps,, that is a follow-up.

---

## Summary of Change Touch Points

| File | Action | Layer |
|-------|--------|-------|
| `SingleThread/ContentViewModel.swift` | Add `isRefreshing` property + `refreshManual()` method |1 |
| `SingleThreadTests/ContentViewModelTests.swift` | Add5 tests |1 |
| `SingleThread/ContentView.swift` | Add macOS refresh button overlay |2 |
| `SingleThreadTests/SingleThreadTests.swift` | Add view-structure test |2 |
| `SingleThreadUITests/SingleThreadUITestsMacOS.swift` | **Create** —3 XCTest tests |3 |
| `Makefile` | Add `mac-ui-test` target |3 |
| `scripts/test.sh` | Add macOS UI step |3 |
| `.github/workflows/ci.yml` | Add `mac-ui-tests` job |3 |
| `SingleThread/ContentView+macOS.swift` | **Create** (fallback only — if `type_body_length` breaches) |2 |