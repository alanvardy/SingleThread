# Implementation Plan — Add iPhone Complete/Skip action buttons (VAR-641)

## Overview

Add an iOS-only Settings toggle "Enable action buttons" (off by default, `.standard`
persistence). When on **and** a visible reminder exists, the iPhone bottom bar renders
Complete (left) / Skip (right) flanking the mic using the watch action-button styling.
Complete is async (`Task { await store.completeCurrentReminder() }`), Skip is sync
(`store.skipCurrentReminder()`). No new `ReminderStore` API or persistence (App Group)
work — only a device-local toggle, view rendering, the Settings surface, and test seams.

**Conventions applied throughout** (from AGENTS.md):
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on for the iOS app target — do **not**
  wrap anything in `Task { @MainActor in }`; `@MainActor` is the default in `ContentView`
  and `SingleThreadApp`.
- Unit tests in `SingleThreadTests/` use Swift Testing (`import Testing`, `@Test`,
  `#expect`). UI tests in `SingleThreadUITests/` use XCTest.
- `SingleThreadApp.swift` needs `import Foundation` (for `UserDefaults.standard`) and
  `import EventKit` (for `EKEventStore`/`EKReminder` in the seam).
- `#if os(iOS)` guards every iOS-only block (toggle, cluster views, cluster branch,
  Settings param).

**Verification map (canonical commands)**:
- `make test` → `./scripts/test.sh --unit-only` (unit suite, incl. new `ActionButtonTests`)
- `make ui-test` → `./scripts/test.sh --ui-only` (UI + accessibility audit)
- `make lint` / `make format`, `make periphery`
- `./scripts/test.sh` — full CI-identical gate (format, lint, build, periphery, unit, UI)
- Explicit unit-only: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`
- Explicit UI-only: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests`

---

## Phase 1: Settings toggle backbone

Persist the "Enable action buttons" toggle on-device and expose it in Settings. The
bottom bar is unchanged (off by default), so app behavior stays identical.

### Changes

#### 1. `SingleThread/ContentView.swift` — new `@AppStorage` toggle
**Action**: modify

Add the iOS-only device-local toggle right after `showMicrophoneButton`
(`ContentView.swift` ~`:184-185`). It intentionally does NOT use `store: AppGroup.defaults`
— it mirrors `showMicrophoneButton`'s `.standard` persistence:

```swift
@AppStorage("showMicrophoneButton")
private var showMicrophoneButton = true

#if os(iOS)
    @AppStorage("enableActionButtons")
    private var enableActionButtons = false
#endif
```

#### 2. `SingleThread/ContentView.swift` — thread the binding into the iOS `.sheet`
**Action**: modify

In `body { ... .sheet(isPresented: $isShowingSettings) { #if os(iOS) SettingsView(...) } }`
(`ContentView.swift` ~`:94-107`), add `enableActionButtons: $enableActionButtons` after
`allowsLandscape: $allowsLandscape`:

```swift
#if os(iOS)
    SettingsView(
        appearanceMode: $appearanceMode,
        textSize: $textSize,
        allowsLandscape: $allowsLandscape,
        enableActionButtons: $enableActionButtons,
        showMicrophoneButton: $showMicrophoneButton,
        showUndatedReminders: $showUndatedReminders,
        excludedProjects: excludedProjectsBinding,
        availableProjects: store.availableProjects,
        sortOption: $sortOption,
        showDate: $showDate)
#else
    // macOS branch UNCHANGED — do not add enableActionButtons here.
#endif
```

#### 3. `SingleThread/SettingsView.swift` — iOS-only init param + `@Binding`
**Action**: modify

**3a.** In iOS `init` (`SettingsView.swift` ~`:62`), add the param after `allowsLandscape`
and assign it:

```swift
init(
    appearanceMode: Binding<AppearanceMode>,
    textSize: Binding<TextSize>,
    allowsLandscape: Binding<Bool>,
    enableActionButtons: Binding<Bool>,
    showMicrophoneButton: Binding<Bool>,
    showUndatedReminders: Binding<Bool>,
    excludedProjects: Binding<Set<String>>,
    availableProjects: [String],
    sortOption: Binding<SortOption>,
    showDate: Binding<Bool>) {
    _appearanceMode = appearanceMode
    _textSize = textSize
    _allowsLandscape = allowsLandscape
    _enableActionButtons = enableActionButtons
    _showMicrophoneButton = showMicrophoneButton
    ...
}
```
Non-iOS `init` is **unchanged**.

**3b.** Add the iOS-only `@Binding` next to `allowsLandscape` (`SettingsView.swift` ~`:177`):

```swift
#if os(iOS)
    @Binding private var allowsLandscape: Bool
    @Binding private var enableActionButtons: Bool
#endif
```

#### 4. `SingleThread/SettingsView.swift` — iOS-only toggle row
**Action**: modify

Add the row next to "Show Microphone" (`SettingsView.swift` ~`:125-126`), between the
Show Microphone `Toggle` and the Show Undated `Toggle`:

```swift
Toggle(isOn: $showMicrophoneButton) {
    Label("Show Microphone", systemImage: "microphone")
}
#if os(iOS)
Toggle(isOn: $enableActionButtons) {
    Label("Enable action buttons", systemImage: "hand.tap")
}
#endif
Toggle(isOn: $showUndatedReminders) { ... }
```
> Note: `hand.tap` is a *choice* of Symbol name. If the SF Symbol doesn't exist in the
> target build (compile/lint error), substitute an existing symbol (e.g. `"hand.point.up"`)
> and update any test assertion that references the row label. The label *text*
> `Enable action buttons` is what's asserted — the symbol name isn't.

**Both iOS `#Preview`s** in `SettingsView.swift` (`Default`, `Dark + Extra Large`) must add
must add `.constant(false)` on the `enableActionButtons` line, right after the
`allowsLandscape` line:

```swift
#Preview("Default") {
    SettingsView(
        appearanceMode: .constant(.system),
        textSize: .constant(.system),
        allowsLandscape: .constant(true),
        enableActionButtons: .constant(false),
        showMicrophoneButton: .constant(true),
        ...
```
Do **NOT** touch the `#else` macOS previews.

#### 5. `SingleThreadTests/SettingsViewTests.swift` — iOS construction + assertion
**Action**: modify

Add `.constant(true)` to the iOS `SettingsView(...)` construction (after
`.allowsLandscape`) and a new assertion. Non-iOS branch untouched.

```swift
let view = SettingsView(
    appearanceMode: .constant(.system),
    textSize: .constant(.system),
    allowsLandscape: .constant(true),
    enableActionButtons: .constant(true),
    showMicrophoneButton: .constant(true),
    ...
)

#expect(bodyDescription.contains("Enable action buttons"))
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — `settingsViewContainsAllPreferenceRows` asserts the new row text.
- [x] `make lint` passes (strict) and `make format` leaves no diffs.

#### Manual
- [ ] Build + run on iPhone 17 sim: gear → Settings shows "Enable action buttons" row with toggle.
- [ ] Toggle on, relaunch the app → toggle still on (`.standard` persistence).
- [ ] App bottom bar visually unchanged when the toggle is off (no cluster, no regression).

---

## Phase 2: Bottom-bar Complete/Skip cluster

Render the full feature: toggle on + visible reminder → Complete/Skip flank the mic with
watch styling; buttons invoke the existing store calls (Complete async, Skip sync).

### Changes

#### 1. `SingleThread/ContentView.swift` — iOS-only action views
**Action**: modify

Add three iOS-only private views. Place them just after the `bottomBar` var
(`ContentView.swift` ~`:399`) and before `// MARK: - Mic Dictation` (order within the
struct doesn't matter; Swift resolves member refs regardless of order). This mirrors the
watch `WatchReminderView.swift:86-101` styling exactly (`checkmark.circle.fill`/`.green`,
`circle.slash`/`.orange`, `.iconOnly`, `.accessibilityLabel(...reminder)`,
`.accessibilityAddTraits(.isButton)`), plus `.frame(width: 44, height: 44)` for symmetry
with the 56pt mic.

```swift
#if os(iOS)
    private var completeButton: some View {
        Button {
            Task { await store.completeCurrentReminder() }
        } label: {
            Label("Complete", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
        }
        .tint(.green)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Complete reminder")
        .accessibilityAddTraits(.isButton)
    }

    private var skipButton: some View {
        Button {
            store.skipCurrentReminder()
        } label: {
            Label("Skip", systemImage: "circle.slash")
                .labelStyle(.iconOnly)
        }
        .tint(.orange)
        .frame(width: 44, height: 44)
        .accessibilityLabel("Skip reminder")
        .accessibilityAddTraits(.isButton)
    }

    private var actionCluster: some View {
        HStack(spacing: 16, alignment: .center) {
            completeButton
            micButton
            skipButton
        }
    }
#endif
```
> The set `Label` text on `completeButton` is `"Complete"` (matching the watch) — NOT
> `"Complete reminder"` — and the accessibility label is `"Complete reminder"`. The test
> assertions key off the accessibility-label strings, which are unique to the new
> bottom-bar buttons (the existing swipe `.accessibilityLabel`s on the card are bare
> `"Complete"`/`"Skip"`, so they never read `"Complete reminder"`/`"Skip reminder"`).

> `micButton` is referenced inside `actionCluster`; it's already a private var on
> `ContentView`. The symmetric 44pt frames keep the 56pt mic visually centered.

#### 2. `SingleThread/ContentView.swift` — gate the mic branching
**Action**: modify

In `bottomBar`, replace the mic branch (`ContentView.swift` ~`:394-395`) so the cluster
renders only when the toggle is on AND a visible reminder exists; otherwise fall back to
the plain mic (mirrors the macOS `actionButtons` gating condition):

```swift
} else if canDictate, showMicrophoneButton {
    #if os(iOS)
        if enableActionButtons, store.visibleReminders.first != nil {
            actionCluster
        } else {
            micButton
        }
    #else
        micButton
    #endif
}
```
The `#else -> micButton` guard is required because `enableActionButtons` is defined only
under `#if os(iOS)`.

#### 3. New `SingleThreadTests/ActionButtonTests.swift`
**Action**: create

Mirrors `MicrophoneToggleTests.swift` (Swift Testing, `@MainActor`). Unlike
`MicrophoneToggleTests`, the fakes there are `private` to their file, so this file defines
its own authorized fake transcriber (pattern copied from `MicToggleTranscriberFake`).

```swift
@testable import SingleThread
import SingleThreadCore
import EventKit
import Speech
import SwiftUI
import Testing

// Fake authorized transcriber (pattern copied from MicrophoneToggleTests; that file's
// fakes are private to its own source file, so not reusable here).
@MainActor
private final class ActionButtonFakeTranscriber: SpeechTranscribing {
    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
    }
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus { authorizationStatus }
    func transcribe(onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String { "" }
}

@MainActor
struct ActionButtonTests {
    // helper: a prepopulated store with one visible reminder; never touches EventKit
    private func storeWithReminder() -> ReminderStore {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = "Buy groceries"
        reminder.priority = 5
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess)
    }

    @Test
    func buttonsShowWhenToggleOnAndReminderVisible() {
        let key = "enableActionButtons"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let store = storeWithReminder()
        let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
        let bodyDescription = String(describing: view.body)

        // Assert on the accessibility-label strings, unique to the new buttons.
        #expect(bodyDescription.contains("Complete reminder"))
        #expect(bodyDescription.contains("Skip reminder"))
    }

    @Test
    func buttonsHiddenWhenToggleOff() {
        let key = "enableActionButtons"
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let store = storeWithReminder()
        let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
        let bodyDescription = String(describing: view.body)
        #expect(!bodyDescription.contains("Complete reminder"))
        #expect(!bodyDescription.contains("Skip reminder"))
    }

    @Test
    func buttonsHiddenWhenNoVisibleReminder() {
        // Empty store -> no visible reminder -> mic branch shows plain micButton.
        let store = ReminderStore(
            loadsReminders: false, reminders: [], skippedIDs: [], authorizationStatus: .fullAccess)
        let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
        let bodyDescription = String(describing: view.body)
        #expect(!bodyDescription.contains("Complete reminder"))
        #expect(!bodyDescription.contains("Skip reminder"))
    }

    @Test
    func buttonsHiddenWhenAllSkipped() {
        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore); reminder.title = "Buy groceries"
        let store = ReminderStore(
            loadsReminders: false, reminders: [reminder],
            skippedIDs: [reminder.calendarItemIdentifier], authorizationStatus: .fullAccess)
        let view = ContentView(store: store, speechTranscriber: ActionButtonFakeTranscriber())
        #expect(!String(describing: view.body).contains("Complete reminder"))
    }
}
```
> The toggle key is set on/off per test with `defer removeObject`, so the `false` default
> is never relied upon across tests.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes — all four `ActionButtonTests` + existing `SettingsViewTests`/`ReminderStoreTests` stay green.
- [x] `make lint` / `make format` pass.

#### Manual
- [ ] Toggle "Enable action buttons" ON with a visible reminder in the iPhone sim → Complete (green, left) and Skip (orange, right) flank the blue mic in the bottom bar.
- [ ] Tap Complete → the card advances and an EventKit write happens (verify the reminder is completed in the Reminders app).
- [ ] Tap Skip → the card advances and the identifier persists to the shared skipped list.
- [ ] With no visible reminder or the toggle off → the plain mic button only.

---

## Phase 3: UI-test seam + accessibility

Makes the new buttons visible to the `--ui-testing` app (currently an **empty** store on
iOS, so the cluster can't render or be audited) and covers them with an interaction +
accessibility test. This is the app entry point → UI test target seam.

### Changes

#### 1. `SingleThread/SingleThreadApp.swift` — deterministic `--ui-testing` seam
**Action**: modify

Mirror the watch seam (`SingleThreadWatchApp.swift:61-77`): when `--ui-testing`, build a
pre-populated store **and** seed the toggle on so the cluster renders for the audit path.

**1a.** Add the imports (mirror the watch app):
```swift
import SingleThreadCore
import SwiftUI
import Foundation          // required for UserDefaults.standard
#if os(iOS)
    import UIKit
    import WatchConnectivity
    import EventKit        // required for EKEventStore / EKReminder in uiTestingStore()
#endif
```

**1b.** Rewrite the store construction in `init()` (`SingleThreadApp.swift:16-20`):
```swift
init() {
    let args = ThePassInfo.processInfo.arguments
    let isUITesting = args.contains("--ui-testing")
    let store: ReminderStore = if isUITesting {
        Self.uiTestingStore()
    } else {
        ReminderStore(loadsReminders: !args.contains("--no-reminders"))
    }
    self.store = store
    store.sortOption = SortOptionStore().load()
    // ... existing iOS / WatchConnectivity wiring unchanged ...
}
```
> Preserves the existing `--no-reminders` path (appearance / cold-launch tests) intact:
> it has no `--ui-testing`, so it still falls to the `else` → empty `loadsReminders: false`.

**1c.** Add the static seam (mirrors watch, placed in the private section), seeding the
toggle so every `--ui-testing` launch exercises the new cluster:
```swift
#if os(iOS)
    /// Builds a deterministic store AND persists the action-buttons toggle on so the
    /// Complete/Skip cluster + reminder card present without EventKit access.
    private static func uiTestingStore() -> ReminderStore {
        UserDefaults.standard.set(true, forKey: "enableActionButtons")
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
#endif
```
> Trade-off: this writes a persistent `.standard` value on the test simulator. It is
> isolated to the XCTest / `--ui-testing` seam on a test-only destination, and is accepted
> because it makes the access/audit path (which launches with only `--ui-testing`)
> exercise the new buttons deterministically. A dedicated launch argument could replace
> this later if a side-effect-free seam is preferred.

> Codegen notice: `SingleThreadApp.swift` is hand-maintained Swift (not code-generated);
> the new file under `SingleThread/` is auto-discovered by Xcode's synchronized file
> groups (`objectVersion = 77`) — no pbxproj edit. If the build initially fails on the
> imports above, re-run the build; do not hand-edit the pbxproj.

#### 2. New `SingleThreadUITests/ActionButtonsUITests.swift` — interaction + audit
**Action**: create (XCTest, mirrors `SingleThreadWatchUITests.swift` patterns)

```swift
import XCTest

final class ActionButtonsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testActionButtonsRenderAndSkipAdvancesCard() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5),
            "Complete button should be present beside the mic")
        let skip = app.buttons["Skip reminder"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
            "Skip button should be present beside the mic")

        // Tap Skip; the settle-delayed skip write advances the visible reminder, which
        // lands on the allSkipped "All Done" branch (bottom bar disappears).
        skip.tap()
        XCTAssertTrue(app.staticTexts["All Done"].waitForExistence(timeout: 5),
            "Skipping should advance the displayed card to the All Done state")
    }

    @MainActor
    func testActionButtonsAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let complete = app.buttons["Complete reminder"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5),
            "Complete button should exist before auditing")
        let skip = app.buttons["Skip reminder"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5),
            "Skip button should exist before auditing")

        try app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])
    }
}
```
> The existing `SingleThreadUITests.swift` `testAccessibilityAudit()` needs **no change** —
> it already launches with `--ui-testing`, and the seam now makes that (a) seed a reminder
> and (b) turn the toggle on, so the audit automatically includes the two new buttons.

### Verification

#### Automated
- [x] `make ui-test` (→ `./scripts/test.sh --ui-only`) passes — both new XCTests (buttons present, skip interaction, audit clean with the new elements).
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes.
- [x] Existing `SingleThreadUITests.swift` `testAccessibilityAudit` still passes (now exercising the new buttons; no hit-region / description / trait failures).

#### Manual
- [ ] Seeded sim launch (`--ui-testing`) shows the cluster (Complete + Skip flanking the mic).
- [ ] Accessibility audit runs green with the two new buttons (no new hit-region / label / trait issues).

---

## Full CI Gate

After all phases, run the complete gate:

- [x] `./scripts/test.sh` passes — SwiftFormat + SwiftLint (`--strict`), build
      (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`), Periphery dead-code scan, unit tests, and
      UI tests (incl. accessibility audit) all green.

---

## Changes Not Made (scope guardrails)

- No change to `ReminderStore` / `EventKitStoring` / `SkippedReminderSyncService` / `AppGroup`.
- No Delete button in the iPhone bottom row, no keyboard shortcuts, no
  `skipCurrentReminderImmediately()`, no widget `Button(intent:)` pattern.
- macOS `actionButtons`, watch `WatchReminderView.actionButtons`, widget surfaces, and the
  iOS `swipeActions` / `.contextMenu` all unchanged.
- No refactoring, cleanup, or improvements to adjacent code.