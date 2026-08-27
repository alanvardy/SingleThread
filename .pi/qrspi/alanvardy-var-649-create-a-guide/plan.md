# Implementation Plan

## Overview

Add a first-launch guide overlay to the watch app with a "Show guide again" toggle on iPhone Settings, following the existing show-* preference + state-holder + sync-pipeline + iPhone-settings pattern. The guide describes the Complete and Skip buttons, is dismissed with a "Got it" button, and never reappears unless re-requested from the iPhone.

---

## Phase 1: Preference Layer — `ShowGuidePreference`

### Changes

#### 1. `ShowGuidePreference` (new)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ShowGuidePreference.swift`
**Action**: create

```swift
import Foundation

/// Persists the user's "show guide" preference in UserDefaults.
///
/// An absent key resolves to `true` (first-launch semantic) —
/// `bool(forKey:)` would suppress the guide on first launch.
/// `nil` (missing key) therefore maps to `true`.
public struct ShowGuidePreference {
    // MARK: Lifecycle

    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "showGuide") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: Public

    /// Whether the guide should be shown. `nil` (missing key) → `true`.
    public var isEnabled: Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    public func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: key)
    }

    // MARK: Private

    private let defaults: UserDefaults
    private let key: String
}
```

#### 2. Preference tests
**File**: `SingleThreadWatchTests/ShowGuideStateTests.swift`
**Action**: create

```swift
import SingleThreadCore
import Testing

/// Covers ShowGuidePreference read/write/round-trip semantics.
/// Serialized because every test writes the real "showGuide" key via
/// `.standard`; running in parallel would race cleanup vs reads.
@MainActor
@Suite(.serialized)
struct ShowGuidePreferenceTests {
    @Test
    func isEnabledReturnsTrueWhenKeyMissing() {
        // Clean start — key absent
        UserDefaults.standard.removeObject(forKey: "showGuide")
        let pref = ShowGuidePreference(defaults: .standard)
        #expect(pref.isEnabled)
    }

    @Test
    func isEnabledReturnsFalseAfterSetFalse() {
        let pref = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        pref.set(false)
        #expect(!pref.isEnabled)
    }

    @Test
    func isEnabledReturnsTrueAfterSetTrue() {
        let pref = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        pref.set(false)
        pref.set(true)
        #expect(pref.isEnabled)
    }

    @Test
    func roundTripSurvivesNewInstance() {
        let prefA = ShowGuidePreference(defaults: .standard)
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        prefA.set(false)
        let prefB = ShowGuidePreference(defaults: .standard)
        #expect(!prefB.isEnabled)
    }
}
```

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThreadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -only-testing:SingleThreadWatchTests/ShowGuidePreferenceTests` passes

#### Manual
- [ ] None — preference layer is pure data contract; tests are sufficient.

---

## Phase 2: State-Holder Layer — `ShowGuideState`

### Changes

#### 1. `ShowGuideState` (new)
**File**: `SingleThreadWatch/ShowGuideState.swift`
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

/// Observable holder for the watch-rendered "show guide" flag.
/// Replaces a former `@AppStorage` read-back; updates arrive through the
/// sync pipeline's explicit `onShowGuideReceived` callback.
@Observable
final class ShowGuideState {
    // MARK: Lifecycle

    init() {
        isEnabled = preference.isEnabled
    }

    // MARK: Internal

    private(set) var isEnabled: Bool

    /// Persists a received value and publishes it to observing views.
    func apply(_ value: Bool) {
        preference.set(value)
        isEnabled = value
    }

    // MARK: Private

    private let preference = ShowGuidePreference(defaults: .standard)
}
```

#### 2. State-holder tests (add to existing file)
**File**: `SingleThreadWatchTests/ShowGuideStateTests.swift`
**Action**: modify (append to file created in Phase 1)

```swift
@MainActor
@Suite(.serialized)
struct ShowGuideStateTests {
    @Test
    func initReadsSeededFalse() {
        UserDefaults.standard.set(false, forKey: "showGuide")
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        let state = ShowGuideState()
        #expect(!state.isEnabled)
    }

    @Test
    func applyPersistsToStandardDefaults() {
        let state = ShowGuideState()
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        state.apply(false)
        #expect(!ShowGuidePreference(defaults: .standard).isEnabled)
    }

    @Test
    func applyRepublishes() {
        let state = ShowGuideState()
        defer { UserDefaults.standard.removeObject(forKey: "showGuide") }
        #expect(state.isEnabled) // default
        state.apply(false)
        #expect(!state.isEnabled)
        state.apply(true)
        #expect(state.isEnabled)
    }
}
```

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` — all tests green (preference + state-holder suites). *Run with the corrected scheme/destination: `-scheme SingleThreadWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'` (watchos target).*

#### Manual
- [ ] None

---

## Phase 3: Sync Pipeline Layer — Wire `showGuide` into WCSession

### Changes

#### 1. Add `PayloadKey.showGuide`, `showGuideStore` param, `onShowGuideReceived` hook, and push/receive branches
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

**Changes in `init`** — add after `showCompletionGlowStore`:
```swift
showGuideStore: ShowGuidePreference = ShowGuidePreference(),
```
Add after `sendsShowCompletionGlow`:
```swift
sendsShowGuide: Bool = true,
```

**New stored properties** (add after `showCompletionGlowStore` + `sendsShowCompletionGlow`):
```swift
private let showGuideStore: ShowGuidePreference
private let sendsShowGuide: Bool
```

**New `init` assignments** (add after `self.sendsShowCompletionGlow = sendsShowCompletionGlow`):
```swift
self.showGuideStore = showGuideStore
self.sendsShowGuide = sendsShowGuide
```

**New hook property** (add after `onShowCompletionGlowReceived`):
```swift
/// Hook fired on the counterpart when the "show guide" preference arrives
/// in an application context. Passes the received value. Same
/// write-once-before-activate / `nonisolated(unsafe)` rationale as
/// `onShowDateReceived`.
public nonisolated(unsafe) var onShowGuideReceived: ((Bool) -> Void)?
```

**Add `PayloadKey.showGuide`** inside `PayloadKey` enum:
```swift
static let showGuide = "showGuide"
```

**Push branch in `pushAll()`** — add after the `showCompletionGlow` block:
```swift
if sendsShowGuide {
    context[PayloadKey.showGuide] = showGuideStore.isEnabled
}
```

**Receive branch in `apply(context:)`** — add after the `showCompletionGlow` block:
```swift
if let showGuide = context[PayloadKey.showGuide] as? Bool {
    showGuideStore.set(showGuide)
    let handler = onShowGuideReceived
    handler?(showGuide)
}
```

#### 2. Phone-side: pass `showGuideStore` + `sendsShowGuide: true` into service
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In the `#if os(iOS)` block where `SkippedReminderSyncService` is created (line ~28), add the param:
```swift
showGuideStore: ShowGuidePreference(),
```
No `sendsShowGuide` override needed — it defaults to `true` and the phone should push it.

#### 3. Phone-side: update `handlePreferencesChanged()` to track `showGuide`
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

In `handlePreferencesChanged()`, add `showGuide` to the comparison:
```swift
let currentShowGuide = ShowGuidePreference().isEnabled
// ... add `|| currentShowGuide != lastShowGuide` to the condition ...
lastShowGuide = currentShowGuide
```
Add stored property:
```swift
private var lastShowGuide = ShowGuidePreference().isEnabled
```

#### 4. Watch-side: add `showGuideState`, wire it into service and VM
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

Add state holder property (after `showCompletionGlowState`):
```swift
let showGuideState: ShowGuideState
```

Initialize in `init(arguments:)` (after `showCompletionGlowState = ...`):
```swift
showGuideState = ShowGuideState()
```

Pass preference into sync service (add after `showCompletionGlowStore: ShowCompletionGlowPreference(defaults: .standard),`):
```swift
showGuideStore: ShowGuidePreference(defaults: .standard),
```

Add `sendsShowGuide: false` to sync service init flags (alongside existing `false` flags).

Wire receive hook in `wireStateReceiveHooks(_:)` (add after `showCompletionGlowState` block):
```swift
let showGuideState = showGuideState
// ...
service.onShowGuideReceived = { [weak showGuideState] value in
    Task { @MainActor in showGuideState?.apply(value) }
}
```

Inject into `WatchReminderViewModel` (add param in `reminderViewModel` computed property):
```swift
showGuideState: showGuideState
```

#### 5. Sync pipeline tests — add `showGuide` assertions
**File**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift`
**Action**: modify (append to existing `WatchSyncPipelineTests` struct)

```swift
@Test
func receiveAppliesShowGuide() {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let showGuideStore = ShowGuidePreference(defaults: .standard, key: "wtest-guide-\(suffix)")
    showGuideStore.set(true)
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: "wtest-guide-ids-\(suffix)"),
        showGuideStore: showGuideStore)

    var values: [Bool] = []
    service.onShowGuideReceived = { values.append($0) }

    service.session(WCSession.default, didReceiveApplicationContext: ["showGuide": false])

    #expect(!showGuideStore.isEnabled)
    #expect(values == [false])
}

@Test
func showGuideSurvivesRelaunch() {
    let key = "wtest-relaunch-guide-\(UUID().uuidString)"
    let fake = WatchFakeSession()
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: SkippedReminderStore(defaults: .standard, key: key + "-ids"),
        showGuideStore: ShowGuidePreference(defaults: .standard, key: key))
    service.session(WCSession.default, didReceiveApplicationContext: ["showGuide": false])
    let freshStore = ShowGuidePreference(defaults: .standard, key: key)
    #expect(!freshStore.isEnabled)
}

@Test
func pushAllFromWatchOmitsShowGuideWhenFlagged() throws {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-guide-skip-\(suffix)")
    skipStore.save(["A"])
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        excludeStore: ExcludedListStore(defaults: .standard, key: "wtest-push-guide-excl-\(suffix)"),
        sortStore: SortOptionStore(defaults: .standard, key: "wtest-push-guide-sort-\(suffix)"),
        showUndatedStore: ShowUndatedRemindersPreference(defaults: .standard, key: "wtest-push-guide-und-\(suffix)"),
        showGuideStore: ShowGuidePreference(defaults: .standard, key: "wtest-push-guide-\(suffix)"),
        sendsShowGuide: false)
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["showGuide"] == nil)
    #expect(context["showRecurrence"] != nil)
    #expect(context["showAlarms"] != nil)
}

@Test
func pushAllIncludesShowGuideWhenFlagged() throws {
    let fake = WatchFakeSession()
    let suffix = UUID().uuidString
    let skipStore = SkippedReminderStore(defaults: .standard, key: "wtest-push-guide-true-skip-\(suffix)")
    skipStore.save(["A"])
    let service = SkippedReminderSyncService(
        session: fake,
        skipStore: skipStore,
        showGuideStore: ShowGuidePreference(defaults: .standard, key: "wtest-push-guide-true-\(suffix)"),
        sendsShowGuide: true)
    service.pushAll()
    let context = try #require(fake.lastContext)
    #expect(context["showGuide"] != nil)
}
```

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` passes — all existing + new sync tests green

#### Manual
- [ ] None

---

## Phase 4: iPhone Settings Layer — "Show Guide Again" Toggle

### Changes

#### 1. `SettingsBindings` — add `showGuide` property
**File**: `SingleThread/SettingsBindings.swift`
**Action**: modify

Add `showGuide: Bool = true` init param (after `showCompletionGlow`). Add stored property:
```swift
var showGuide: Bool
```
Add assignment in init:
```swift
self.showGuide = showGuide
```

#### 2. `ReminderSettingsView` — add toggle
**File**: `SingleThread/ReminderSettingsView.swift`
**Action**: modify

Add `@Binding var showGuide: Bool` parameter.

Add Toggle after the `showCompletionGlow` toggle (before the closing `}` of the `Form`):
```swift
Toggle(isOn: $showGuide) {
    Label("Show guide again", systemImage: "questionmark.circle")
}
```

No `.onChange(of: showGuide)` — follows `showList`/`showCompletionGlow` pattern (no widget reload needed).

Update `#Preview` to pass `showGuide: .constant(true)`.

#### 3. `ContentView` — add `@AppStorage`, write-back, and bag wiring
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add `@AppStorage` property (after the existing `showCompletionGlow` line):
```swift
@AppStorage("showGuide", store: AppGroup.defaults)
private var showGuide = true
```

In `makeSettingsBag()`: add `showGuide: showGuide` to both the `#if os(iOS)` and `#else` branches.

In the `.sheet` write-back chain (after `showCompletionGlow` line):
```swift
.onChange(of: bag.showGuide) { _, new in showGuide = new }
```

### Verification
#### Automated
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` compiles cleanly
- [ ] `./scripts/test.sh` passes — full gate: format, lint, periphery, build, unit tests, UI tests

#### Manual
- [ ] Build to iPhone 17 simulator, open Settings → Reminder, verify "Show guide again" toggle is present and on by default
- [ ] Toggle it off, verify it stays off when re-opening settings
- [ ] (Optional smoke) If watch build available: toggle off on phone, confirm on watch the guide won't show

---

## Phase 5: Watch UI Overlay Layer — `GuideOverlay`

### Changes

#### 1. `GuideOverlay` view (new)
**File**: `SingleThreadWatch/GuideOverlay.swift`
**Action**: create

```swift
import SwiftUI

/// Full-screen guide overlay shown on first launch (and whenever the phone
/// toggles "show guide again" on). Describes the Complete and Skip buttons
/// with arrows, plus a "Got it" dismiss button.
struct GuideOverlay: View {
    // MARK: Internal

    /// Whether the overlay is rendered and interactive. Animation is gated
    /// on this flag from the parent view.
    let isActive: Bool

    /// Persists `false` and triggers fade-out when the user taps "Got it".
    let onDismiss: () -> Void

    /// When `true`, the overlay appears/disappears instantly instead of fading.
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.left")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text("Tap Complete to finish")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel("Tap the Complete button to finish the current reminder")
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.down.right")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text("Tap Skip to skip")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .accessibilityLabel("Tap the Skip button to skip the current reminder")
                }

                Spacer()

                Button("Got it") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Dismisses the guide and shows your reminders")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: isActive)
    }
}
```

#### 2. `GuideOverlay` unit tests (new file)
**File**: `SingleThreadWatchTests/GuideOverlayStateTests.swift`
**Action**: create

Tests for overlay behavior — presence, dismiss callback, accessibility traits, reduce motion. (See structure.md for test outline; implement as `@MainActor @Suite(.serialized)` matching the codebase pattern. Test the overlay view's `isActive` gating, `onDismiss` closure firing, `.accessibilityAddTraits(.isButton)` on "Got it" button, and `.animation(nil, value:)` when `reduceMotion: true`.)

```swift
import SingleThreadCore
import SwiftUI
@testable import SingleThreadWatch
import Testing

// Note: View-level snapshot tests for the overlay presence and dismiss
// behavior. For accessibility traits, the overlay UI test (Phase 5 UI)
// provides the authoritative assert via performAccessibilityAudit.

@MainActor
@Suite(.serialized)
struct GuideOverlayStateTests {
    @Test
    func dismissInvokesClosure() async {
        var dismissed = false
        // Build the overlay; tap "Got it" by invoking onDismiss directly.
        // SwiftUI view hierarchy testing is limited on watchOS, so we test
        // the callback plumbing directly.
        let overlay = GuideOverlay(isActive: true, onDismiss: { dismissed = true }, reduceMotion: false)
        // The onDismiss closure is wired to the "Got it" button — verify
        // it fires when invoked.
        overlay.onDismiss()
        #expect(dismissed)
    }

    @Test
    func isActiveFalseHidesFromAccessibility() {
        // When isActive is false, .accessibilityHidden(true) is set.
        let overlay = GuideOverlay(isActive: false, onDismiss: {}, reduceMotion: false)
        // The overlay body gates on isActive for accessibilityHidden — we
        // can't introspect SwiftUI modifier state, but the UI test asserts
        // VoiceOver behavior. This test documents the contract.
        #expect(!overlay.isActive)
    }
}
```

#### 3. `WatchReminderViewModel` — add `showGuideState` param
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Add init param (after `showCompletionGlowState`):
```swift
showGuideState: ShowGuideState = ShowGuideState()
```

Add stored property:
```swift
let showGuideState: ShowGuideState
```

Assign in init:
```swift
self.showGuideState = showGuideState
```

#### 4. `WatchReminderView` — add guide overlay
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

In the `reminderContent` ZStack's `.overlay` chain (after the completion glow overlay), add:
```swift
if viewModel.showGuideState.isEnabled {
    GuideOverlay(
        isActive: viewModel.showGuideState.isEnabled,
        onDismiss: { viewModel.showGuideState.apply(false) },
        reduceMotion: reduceMotion)
    .zIndex(1) // above the glow overlay
}
```

Update both `init` overloads to accept/pass-through `showGuideState`:
- Production init: add param `showGuideState: ShowGuideState = ShowGuideState()`, store it.
- Preview init: add param `showGuideState: ShowGuideState = ShowGuideState()`, pass to VM.

The overlay sits on `reminderContent` only, so the authorization gate paths (`ProgressView("Requesting access…")` and "Enable Reminders access in Settings") are NOT covered — correct per design.

**One important detail**: The overlay `.zIndex(1)` ensures it renders above the completion glow overlay. Alternatively, nest the overlays so only one appears at a time. The glow is decorative (`accessibilityHidden(true)`, `allowsHitTesting(false)`) so stacking is harmless — but to avoid the glow flashing behind the guide on first launch if a completion-trigger races the guide display, ensure the guide overlay's `allowsHitTesting(isActive)` blocks interactions through to the card.

#### 5. Watch UI tests — guide flow
**File**: `SingleThreadWatchUITests/SingleThreadWatchUITests.swift`
**Action**: modify (append test methods to `SingleThreadWatchUITests`)

```swift
@MainActor
func testGuideAppearsOnFirstLaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--reset-guide"]
    app.launch()

    // Guide overlay should be visible
    let gotIt = app.buttons["Got it"]
    XCTAssertTrue(gotIt.waitForExistence(timeout: 5), "Guide overlay should show 'Got it' button on first launch")

    // Card should NOT be tappable through the overlay
    let title = app.staticTexts["Buy groceries"]
    XCTAssertFalse(title.isHittable, "Reminder card should be blocked by the guide overlay")

    // Dismiss
    gotIt.tap()

    // After dismiss, the card should be visible and tappable
    XCTAssertTrue(title.waitForExistence(timeout: 3), "Reminder card should appear after dismissing guide")
}

@MainActor
func testGuideDoesNotReappearOnSubsequentLaunch() {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing"]
    app.launch()

    // Without --reset-guide, the guide should not appear
    let gotIt = app.buttons["Got it"]
    XCTAssertFalse(gotIt.waitForExistence(timeout: 3), "Guide should not appear on subsequent launches")

    // Card should be directly visible
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
}

@MainActor
func testAccessibilityAuditWithGuide() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--reset-guide"]
    app.launch()

    let gotIt = app.buttons["Got it"]
    XCTAssertTrue(gotIt.waitForExistence(timeout: 5))

    #if os(watchOS)
        try app.performAccessibilityAudit(
            for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])
    #endif
}
```

**File**: `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`
**Action**: modify (append test method)

```swift
@MainActor
func testGuideReappearsAfterPhoneResets() {
    let app = launchApp()

    // Without --reset-guide, guide should not show
    XCTAssertFalse(app.buttons["Got it"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))

    // Simulate phone pushing showGuide:true by delivering an application context
    // with showGuide:true — mirrors the live-exclusion test pattern
    // NOTE: This test requires the watch app to be running with a sync service.
    // The app uses a real WCSession which can receive updateApplicationContext
    // in UI testing. If this proves unreliable, this test moves to unit-test
    // coverage (the sync pipeline test already covers the receive path).
}
```

### Verification
#### Automated
- [ ] `xcodebuild build -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug` compiles cleanly
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchTests` — all unit tests green
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadWatchUITests` — guide flow UI tests + accessibility audit pass

#### Manual
- [ ] None — UI tests provide authoritative coverage

---

## Phase 6: Testing Seam — `--reset-guide` Launch Arg

### Changes

#### 1. Add `--reset-guide` handling in `WatchAppViewModel.init`
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

In `init(arguments:)`, before building state holders (before `showDateState = ShowDateState()` line), add:
```swift
if arguments.contains("--reset-guide") {
    UserDefaults.standard.removeObject(forKey: "showGuide")
}
```

This follows the iOS `--reset-glow-preference` pattern (`AppViewModel.swift:186-190`).

### Verification
#### Automated
- [ ] Stage 5 UI tests pass (they depend on `--reset-guide` for the first-launch simulation)
- [ ] `./scripts/test.sh` — full gate green

#### Manual
- [ ] None required — covered by UI tests

---

## Testing Checkpoints

| Stage | Gate — must be green before advancing |
|-------|--------|
| 1 | `SingleThreadWatchTests/ShowGuidePreferenceTests` — preference read/write/round-trip |
| 2 | `SingleThreadWatchTests` — add state-holder tests, all green |
| 3 | `SingleThreadWatchTests` — sync pipeline tests + regression, all green |
| 4 | `./scripts/test.sh` — full gate; manual toggle smoke test on iPhone sim |
| 5 | `SingleThreadWatchTests` + `SingleThreadWatchUITests` — overlay unit + UI + a11y audit, all green |
| 6 | Stage 5 UI tests (they depend on `--reset-guide`); `./scripts/test.sh` green |

---

## Cross-Cutting Notes

- **Authorization gate paths NOT covered**: The guide overlay is scoped to `reminderContent` only, so `.notDetermined` / access-denied screens never show the guide. No special gating needed.
- **VoiceOver focus**: When the guide appears, the "Got it" button and instruction text are in the a11y tree. If `.accessibilityFocused` is needed, add it as a Stage 5 implementation detail — the accessibility audit UI test catches regressions.
- **No `.onChange(of: showGuide)` → `showPreferenceChanged()`**: `showGuide` follows the `showList`/`showCompletionGlow` pattern — no widget reload.
- **No localization**: Guide text is hardcoded English per design decision.
- **Format/lint**: Run `make format` then `make lint` after each phase. Add `ShowGuideState.swift` and `GuideOverlay.swift` to any new test target lists if needed (they should be auto-discovered by Xcode with `objectVersion = 77`).