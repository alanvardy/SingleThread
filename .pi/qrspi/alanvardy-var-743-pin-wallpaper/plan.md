# Implementation Plan

## Overview

Add a "Pin wallpaper" toggle that gates auto-refresh in `BackgroundImageStore`
without blocking manual refresh. Implemented bottom-up: store gating logic with
unit tests first, then the five-step settings pipe + UI wiring, then UI-test
infrastructure with a cross-relaunch persistence test.

---

## Phase 1: `BackgroundImageStore` Pin Gating

### Changes

#### 1. Add `isPinned` property and `setPinned(_:)` mutator

**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

Add a new observable property after `isRefreshing` (after line 76):

```swift
/// When true, `refreshIfNeeded` treats the wallpaper as perpetually fresh.
/// Manual `forceRefresh` is unaffected. Set by the view layer from the
/// `@AppStorage("backgroundPinned")` preference.
private(set) var isPinned = false
```

Add the mutator method after `forceRefresh()` (after the closing `}` of
`forceRefresh`, around line 116):

```swift
/// Updates the pin state. When transitioning from pinned → unpinned,
/// immediately checks freshness and refetches if the photo is stale.
func setPinned(_ pinned: Bool) async {
    let wasPinned = isPinned
    isPinned = pinned
    if !pinned, wasPinned {
        await refreshIfNeeded()
    }
}
```

#### 2. Gate `refreshIfNeeded` on `isPinned`

**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

Insert the pin guard after `loadStoredImage()` in `refreshIfNeeded(maxAge:)`
(after line 92):

```swift
func refreshIfNeeded(maxAge: TimeInterval = BackgroundImageStore.defaultMaxAge) async {
    loadStoredImage()
    guard !isPinned else { return }          // ← new gate
    guard !isFresh(maxAge: maxAge) else { return }
    do {
        try await fetchAndPersist(from: Self.endpoint)
    } catch {
        Self.logger.error("Background refresh failed: \(error.localizedDescription)")
    }
}
```

#### 3. Add unit tests for pin gating

**File**: `SingleThreadTests/BackgroundImageStoreTests.swift`
**Action**: modify

Add five tests after the last existing test (after `isRefreshingToggledDuringForceRefresh`,
around line 252). All reuse the existing `makeStore(client:)` helper and
`FakeBackgroundFetcher`.

```swift
// MARK: - Pin gating

@Test
func pinBlocksRefreshIfNeeded() async {
    let fake = FakeBackgroundFetcher()
    let (store, _) = makeStore(client: fake)

    // Seed a stale sidecar so refreshIfNeeded would normally fetch.
    let staleDate = Date().addingTimeInterval(-25 * 3600)
    try! sidecarJSON(fetchedAt: staleDate)
        .write(to: store.metadataURL, options: .atomic)
    try! BackgroundTestFixtures.jpegData
        .write(to: store.imageURL, options: .atomic)
    store.loadStoredImage()

    // Stub the endpoint to confirm it is NOT called.
    fake.stubbedData[Self.endpoint] = .success(payloadJSON())
    fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

    await store.setPinned(true)
    await store.refreshIfNeeded()

    #expect(fake.requestedURLs.isEmpty,
        "Pinned store should skip network on refreshIfNeeded")
}

@Test
func forceRefreshBypassesPin() async {
    let fake = FakeBackgroundFetcher()
    let (store, _) = makeStore(client: fake)

    fake.stubbedData[Self.randomEndpoint] = .success(payloadJSON())
    fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

    await store.setPinned(true)
    await store.forceRefresh()

    #expect(fake.requestedURLs.contains(Self.randomEndpoint),
        "forceRefresh should fetch randomEndpoint even when pinned")
}

@Test
func unpinTriggersRefreshWhenStale() async {
    let fake = FakeBackgroundFetcher()
    let (store, _) = makeStore(client: fake)

    // Seed a stale sidecar.
    let staleDate = Date().addingTimeInterval(-25 * 3600)
    try! sidecarJSON(fetchedAt: staleDate)
        .write(to: store.metadataURL, options: .atomic)
    try! BackgroundTestFixtures.jpegData
        .write(to: store.imageURL, options: .atomic)
    store.loadStoredImage()

    fake.stubbedData[Self.endpoint] = .success(payloadJSON())
    fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

    // Pin, then unpin.
    await store.setPinned(true)
    #expect(store.isPinned)
    await store.setPinned(false)

    #expect(!store.isPinned)
    #expect(fake.requestedURLs.contains(Self.endpoint),
        "Unpinning a stale store should trigger refreshIfNeeded")
}

@Test
func unpinDoesNotRefreshWhenFresh() async {
    let fake = FakeBackgroundFetcher()
    let (store, _) = makeStore(client: fake)

    // Seed a fresh sidecar.
    let freshDate = Date().addingTimeInterval(-1 * 3600)
    try! sidecarJSON(fetchedAt: freshDate)
        .write(to: store.metadataURL, options: .atomic)
    try! BackgroundTestFixtures.jpegData
        .write(to: store.imageURL, options: .atomic)
    store.loadStoredImage()

    // Stub to confirm endpoint is NOT called.
    fake.stubbedData[Self.endpoint] = .success(payloadJSON())
    fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

    await store.setPinned(true)
    await store.setPinned(false)

    #expect(fake.requestedURLs.isEmpty,
        "Unpinning a fresh store should not trigger a fetch")
}

@Test
func unpinOnlyTriggersOnTrueToFalseTransition() async {
    let fake = FakeBackgroundFetcher()
    let (store, _) = makeStore(client: fake)

    // Seed a stale sidecar.
    let staleDate = Date().addingTimeInterval(-25 * 3600)
    try! sidecarJSON(fetchedAt: staleDate)
        .write(to: store.metadataURL, options: .atomic)
    try! BackgroundTestFixtures.jpegData
        .write(to: store.imageURL, options: .atomic)
    store.loadStoredImage()

    fake.stubbedData[Self.endpoint] = .success(payloadJSON())
    fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)

    // Already unpinned (default) — calling setPinned(false) should be a no-op.
    await store.setPinned(false)

    #expect(fake.requestedURLs.isEmpty,
        "setPinned(false) on already-unpinned store should not fetch")
}
```

**Note**: The new tests reference `store.metadataURL` and `store.imageURL` —
these are currently `private`. Expose them as `internal` for testing:

**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

Change the two private URL properties (around lines 78-84) from `private` to
no access modifier (internal):

```swift
// Before:
private var imageURL: URL { … }
private var metadataURL: URL { … }

// After (remove `private`):
var imageURL: URL { … }
var metadataURL: URL { … }
```

The `loadStoredImage()` method must also be accessible from tests — change
from `private func` to `func`:

```swift
// Before:
private func loadStoredImage() { … }

// After:
func loadStoredImage() { … }
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes (all 12 existing + 5 new `BackgroundImageStoreTests`)

#### Manual
- [ ] None — all behavior is covered by unit tests with injected fakes. No UI wiring yet.

---

## Phase 2: Settings Pipe + UI Wiring

### Changes

#### 1. Add `@AppStorage("backgroundPinned")` in ContentView

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add after the existing `backgroundFadePercent` declaration (after line 169):

```swift
@AppStorage("backgroundPinned", store: .standard)
private var backgroundPinned = false
```

#### 2. Propagate pin to store in `.task` + add `.onChange`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `.task` modifier (around line 88-90), call `setPinned` before
`viewModel.task`:

```swift
.task {
    viewModel.backgroundImage.setPinned(backgroundPinned)
    await viewModel.task(showUndatedReminders: showUndatedReminders)
}
```

Add a new `.onChange` after the existing `.onChange(of: showUndatedReminders)`
block (after line 93):

```swift
.onChange(of: backgroundPinned) { _, newValue in
    Task { await viewModel.backgroundImage.setPinned(newValue) }
}
```

#### 3. Write-back in settings sheet `.onChange`

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add after the `backgroundFadePercent` write-back (after line 130):

```swift
.onChange(of: bag.backgroundPinned) { _, new in backgroundPinned = new }
```

#### 4. Pass `backgroundPinned` in `makeSettingsBag()` — both branches

**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `#if os(iOS)` branch (around line 546), add after `backgroundFadePercent`:

```swift
backgroundPinned: backgroundPinned,
```

In the `#else` branch (around line 560), add after `backgroundFadePercent`:

```swift
backgroundPinned: backgroundPinned,
```

#### 5. Add `backgroundPinned` to `SettingsBindings`

**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add to the `init` parameter list after `backgroundFadePercent: Int = 50,`
(around line 27):

```swift
backgroundPinned: Bool = false,
```

In the `init` body, add after `self.backgroundFadePercent = backgroundFadePercent`
(around line 43):

```swift
self.backgroundPinned = backgroundPinned
```

Add the `var` declaration after `var backgroundFadePercent: Int` (around line 60):

```swift
var backgroundPinned: Bool
```

#### 6. Add Pin toggle in `BackgroundSettingsView`

**File**: `SingleThread/BackgroundSettingsView.swift`
**Action**: modify

Add a new `@Binding` after `@Binding var backgroundFadePercent: Int` (around
line 11):

```swift
@Binding var backgroundPinned: Bool
```

Add a new `Section` with the toggle in `body`, after the Background Fade
`Picker` block (after line 22) and before the Refresh button `Section` (before
line 24). Wrap it in `if backgroundEnabled`:

```swift
if backgroundEnabled {
    Section {
        Toggle(isOn: $backgroundPinned) {
            Label("Pin wallpaper", systemImage: "pin")
        }
    }
}
```

#### 7. Forward the binding in `SettingsView`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

In the `BackgroundSettingsView` instantiation (around lines 76-80), add the
new binding:

```swift
BackgroundSettingsView(
    backgroundEnabled: $bindings.backgroundEnabled,
    backgroundFadePercent: $bindings.backgroundFadePercent,
    backgroundPinned: $bindings.backgroundPinned,
    backgroundImage: backgroundImage)
```

#### 8. Update previews to compile

**File**: `SingleThread/BackgroundSettingsView.swift`
**Action**: modify

In the `#Preview` at the bottom of the file, add the new binding to each
`BackgroundSettingsView` initializer in previews:

```swift
backgroundPinned: .constant(false),
```

#### 9. Add SettingsViewTests for the pin toggle

**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add after `backgroundSettingsViewContainsExpectedRows` (after line 129):

```swift
@Test
func backgroundSettingsViewContainsPinToggle() async {
    let store = await makeSeededStore()
    let view = BackgroundSettingsView(
        backgroundEnabled: .constant(true),
        backgroundFadePercent: .constant(50),
        backgroundPinned: .constant(false),
        backgroundImage: store)
    let bodyDescription = String(describing: view.body)

    #expect(bodyDescription.contains("Pin wallpaper"),
        "Background settings should contain Pin wallpaper toggle when background is enabled")
}

@Test
func pinToggleHiddenWhenBackgroundDisabled() async {
    let store = await makeSeededStore()
    let view = BackgroundSettingsView(
        backgroundEnabled: .constant(false),
        backgroundFadePercent: .constant(50),
        backgroundPinned: .constant(false),
        backgroundImage: store)
    let bodyDescription = String(describing: view.body)

    #expect(!bodyDescription.contains("Pin wallpaper"),
        "Pin wallpaper toggle should be hidden when background is disabled")
}
```

Update the existing `backgroundSettingsViewContainsExpectedRows` test
(around line 115) to add the new binding parameter and include "Pin wallpaper"
in its expected labels:

```swift
@Test
func backgroundSettingsViewContainsExpectedRows() async {
    let store = await makeSeededStore()
    let view = BackgroundSettingsView(
        backgroundEnabled: .constant(true),
        backgroundFadePercent: .constant(50),
        backgroundPinned: .constant(false),
        backgroundImage: store)
    let bodyDescription = String(describing: view.body)

    let expectedLabels = ["Background", "Background Fade", "Pin wallpaper", "Unsplash"]
    for label in expectedLabels {
        #expect(bodyDescription.contains(label))
    }
}
```

### Verification

#### Automated
- [x] Build compiles: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — all `BackgroundImageStoreTests` (17 total) + all `SettingsViewTests` (including the 2 new pin toggle tests and the updated `backgroundSettingsViewContainsExpectedRows`)

#### Manual
- [ ] Launch app in simulator, open Settings → Background — "Pin wallpaper" toggle visible in its own Section between the fade picker and refresh button
- [ ] Toggle `backgroundEnabled` off — "Pin wallpaper" toggle hides
- [ ] Toggle `backgroundEnabled` back on — "Pin wallpaper" toggle reappears

---

## Phase 3: UI Test Infrastructure + Cross-Relaunch Test

### Changes

#### 1. Add missing keys to `persistedKeys`

**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

Add `"backgroundPinned"` and `"backgroundFadePercent"` to the `persistedKeys`
array (around lines 56-75), so both are wiped on `--seed` launch:

```swift
private static let persistedKeys = [
    "skippedReminderIdentifiers",
    "excludedListTitles",
    "showDate",
    "showList",
    "showRecurrence",
    "showAlarms",
    "showCompletionGlow",
    "showUndatedReminders",
    "sortOption",
    "completionCount",
    "isEntitled",
    "enableActionButtons",
    "showMicrophoneButton",
    "showSwipePrompt",
    "backgroundEnabled",
    "backgroundFadePercent",
    "backgroundPinned",
    "allowsLandscape",
    "textSize",
    "appearanceMode"
]
```

#### 2. Add UI test for pin toggle persistence

**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add after `testBackgroundToggleHidesAndPersistsAcrossRelaunch` (after line 232):

```swift
// MARK: - Pin wallpaper toggle

@MainActor
func testPinWallpaperTogglePersistsAcrossRelaunch() {
    let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()

    // Navigate into the Background sub-view.
    XCTAssertTrue(app.staticTexts["Background"].waitForExistence(timeout: 3))
    app.staticTexts["Background"].tap()

    let pinToggle = app.switches["Pin wallpaper"]
    XCTAssertTrue(pinToggle.waitForExistence(timeout: 3))
    XCTAssertEqual(pinToggle.value as? String, "0", "Pin wallpaper should default to off")

    // Flip on.
    XCTAssertTrue(flipToggle(pinToggle, target: "1"))

    // Back-navigate → Done → terminate.
    app.navigationBars.buttons.firstMatch.tap()
    app.buttons["Done"].tap()
    app.terminate()

    // Relaunch with --ui-testing to avoid resetPersistedState() wipe.
    let relaunched = XCUIApplication()
    relaunched.launchArguments = ["--ui-testing"]
    relaunched.launch()
    relaunched.buttons["Settings"].tap()
    relaunched.staticTexts["Background"].tap()
    let persistedToggle = relaunched.switches["Pin wallpaper"]
    XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(
        persistedToggle.value as? String, "1",
        "Pin wallpaper on should persist across relaunch")

    // Flip back off and verify it persists as off (not a one-way latch).
    XCTAssertTrue(flipToggle(persistedToggle, target: "0"))
    relaunched.navigationBars.buttons.firstMatch.tap()
    relaunched.buttons["Done"].tap()
    relaunched.terminate()

    let thirdLaunch = XCUIApplication()
    thirdLaunch.launchArguments = ["--ui-testing"]
    thirdLaunch.launch()
    thirdLaunch.buttons["Settings"].tap()
    thirdLaunch.staticTexts["Background"].tap()
    let offToggle = thirdLaunch.switches["Pin wallpaper"]
    XCTAssertTrue(offToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(
        offToggle.value as? String, "0",
        "Pin wallpaper off should persist across relaunch")
}
```

### Verification

#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes for `testPinWallpaperTogglePersistsAcrossRelaunch`
- [ ] Existing UI test `testBackgroundToggleHidesAndPersistsAcrossRelaunch` still passes (no regression from `persistedKeys` changes)
- [ ] Full gate: `./scripts/test.sh` passes

#### Manual
- [ ] None — the UI test covers the full cross-relaunch flow.

---

## Final Verification

After all three phases are complete:

- [ ] `./scripts/test.sh` passes — format, lint, build, Periphery, unit tests, UI tests

---

## Ordering & Dependencies

```
Phase 1 (store gating)
  └── Phase 2 (settings pipe + UI)
        └── Phase 3 (UI test + persistedKeys)
```

Each phase must complete and verify before starting the next. The full gate
(`./scripts/test.sh`) only needs to pass at the end, but the phase-level
verification commands must pass before advancing.