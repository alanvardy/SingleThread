# Implementation Plan

## Overview

Decompose `SingleThread/ContentView.swift` (817 raw / 815 measured / 563 struct-body lines) by moving three self-contained regions into sibling `extension ContentView` files, then restore the `file_length` warning threshold to 650 and remove both `swiftlint:disable` directives. Pure code movement — no behavior change, no new View types, no new tests.

**Environment note (this machine):** the name-only `iPhone 17` destination is ambiguous with 4 runtimes and a bare `name=` hangs. Pin it for every build/test command below:
```bash
# find an OS version or UDID:
xcrun simctl list devices available | grep -iE 'iphone|ipad'
# then prefix make/test.sh invocations with, e.g.:
SIM='platform=iOS Simulator,name=iPhone 17,OS=18.7' make build
```
`make` and `scripts/test.sh` accept `SIM=` (see AGENTS.md). Every command below that runs a simulator should be prefixed with a pinned `SIM=...`.

Expected line counts as checkpoints: after Stage 1 ≈ **739**, after Stage 2 ≈ **687**, after Stage 3 ≈ **610** (`wc -l SingleThread/ContentView.swift`).

---

## Phase 1: Previews → `ContentView+Previews.swift`

Move the preview fixtures and six `#Preview` blocks out of `ContentView.swift`. Lowest-risk split: nothing in the app or tests executes this code.

### Changes

#### 1. Create `SingleThread/ContentView+Previews.swift`
**File**: `SingleThread/ContentView+Previews.swift`
**Action**: create

Move, verbatim, the current preview helpers (`private let mockPreviewEventStore`, `mockReminder`, `mockReminderInList`) and all six `#Preview` blocks. The file content is exactly:

```swift
import EventKit
import SingleThreadCore
import SwiftUI

// MARK: - Preview Helpers

/// A single `EKEventStore` kept alive to back the preview reminders. The
/// backing store must outlive the reminders — `EKReminder` holds a weak
/// reference to it, so a deallocated store crashes canvas with SIGTRAP.
private let mockPreviewEventStore = EKEventStore()

private let mockReminder: EKReminder = {
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.dueDateComponents = DateComponents(year: 2024, month: 9, day: 15, hour: 14, minute: 0)
    reminder.notes = "Don't forget the milk"
    reminder.url = URL(string: "https://example.com/shopping-list")
    reminder.addRecurrenceRule(EKRecurrenceRule(
        recurrenceWith: .weekly, interval: 1, end: nil))
    return reminder
}()

private let mockReminderInList: EKReminder = {
    let calendar = EKCalendar(for: .reminder, eventStore: mockPreviewEventStore)
    calendar.title = "Groceries"
    let reminder = EKReminder(eventStore: mockPreviewEventStore)
    reminder.title = "Buy milk"
    reminder.calendar = calendar
    return reminder
}()

// MARK: - Previews

#Preview("Empty") {
    ContentView(
        loadsReminders: false,
        eventStore: InMemoryEventStore())
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("Nothing Due") {
    ContentView(
        loadsReminders: false,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        hasHidden: true)
}

#Preview("With Reminder") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
        .preferredColorScheme(AppearanceMode.dark.colorScheme)
}

#Preview("All Skipped") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminder],
        skippedIDs: [mockReminder.calendarItemIdentifier],
        authorizationStatus: .fullAccess)
}

#Preview("All Excluded") {
    ContentView(
        loadsReminders: false,
        reminders: [mockReminderInList],
        skippedIDs: [],
        authorizationStatus: .fullAccess,
        excludedListTitles: ["Groceries"])
}

#Preview("No Access") {
    ContentView(
        loadsReminders: true,
        reminders: [],
        skippedIDs: [],
        authorizationStatus: .denied)
}
```

The `#Preview` blocks reference `AppearanceMode.dark.colorScheme` and `InMemoryEventStore` (both `SingleThreadCore`) and `EKEventStore`/`EKReminder`/`EKCalendar` (`EventKit`) — hence the three imports. The `private` fixtures stay file-private; no access-control change.

#### 2. Delete preview section from `SingleThread/ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete everything from the `// MARK: - Preview Helpers` comment through the final `#Preview("No Access")` block (end of file). The file now ends at the iOS extension's `#endif` (Stage 1 leaves the extension in place).

**Keep** `import EventKit` — the struct's `init(loadsReminders:reminders:…)` signature still uses `EKReminder`/`EKAuthorizationStatus`.

### Verification
#### Automated
- [x] `SIM='…' make build` succeeds
- [ ] `SIM='…' ./scripts/test.sh --unit-only` passes (guards: `SingleThreadTests.swift:15,26` and `MicrophoneToggleTests.swift:39,66,83,99` instantiate `ContentView` and must still compile/pass)
- [x] `make lint` returns 0 (SwiftFormat + `swiftlint lint --strict`)

#### Manual
- [ ] `wc -l SingleThread/ContentView.swift` ≈ 739
- [ ] Open Xcode, select the canvas for any `#Preview` in the new file — previews render (or at minimum the target still builds with previews discoverable)

---

## Phase 2: iOS notifications extension → `ContentView+iOS.swift`

Move the file-scope `private extension ContentView` (notifications) into its own sibling file as an **internal** extension.

### Changes

#### 1. Create `SingleThread/ContentView+iOS.swift`
**File**: `SingleThread/ContentView+iOS.swift`
**Action**: create

Content (members moved verbatim; `private extension` becomes `extension`):

```swift
import SingleThreadCore
import SwiftUI

// MARK: - Notifications (iOS)

// Notification scheduling handlers and the UI-test seam overlay. Kept in a
// separate extension so `ContentView`'s own body stays within SwiftLint's
// `type_body_length` budget.
#if os(iOS)
    extension ContentView {
        /// True only for the notifications scheduling UI test; exposes the pending /
        /// last-schedule status strings to the accessibility tree in that mode so an
        /// XCUITest can assert the app's real pending-notification state.
        var isNotificationsUITesting: Bool {
            ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications")
        }

        /// UI-test seam: renders the pending/last-schedule notification status
        /// strings so an XCUITest can read the app's real pending state. Only
        /// ever present in the view hierarchy under `--ui-testing-notifications`
        /// (the call site gates on `isNotificationsUITesting`), so production
        /// and accessibility audits never see it.
        var notificationStatusOverlay: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(appViewModel?.pendingSummary ?? "unset")
                    .accessibilityIdentifier("pendingStatus")
                Text(appViewModel?.lastScheduleSummary ?? "unset")
                    .accessibilityIdentifier("lastScheduleStatus")
            }
            .font(.system(size: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(!isNotificationsUITesting)
        }

        /// Routes scene-phase transitions into the notification engine: schedule on
        /// background, cancel on foreground. No-op on non-iOS platforms (the feature
        /// is iOS-only).
        func handleScenePhaseChange(_ phase: ScenePhase) {
            guard let appViewModel else { return }
            switch phase {
            case .background:
                Task { await appViewModel.scheduleNotificationIfNeeded() }
            case .active:
                Task { await appViewModel.cancelNotifications() }
            default:
                break
            }
        }

        /// Requests notification authorization the first time the user flips the
        /// enable toggle ON, and cancels all pending requests when flipped OFF.
        func handleNotificationsEnabledChange(_ newValue: Bool) {
            if newValue {
                Task { await appViewModel?.requestNotificationPermissionIfNeeded() }
            } else {
                Task { await appViewModel?.cancelNotifications() }
            }
        }
    }
#endif
```

The call sites stay in `ContentView.swift` (`body`'s `.onChange(of: scenePhase)`, `.onChange(of: notificationsEnabled)`, and the `isNotificationsUITesting` overlay check), so all four members must be internal (drop `private`). `ScenePhase`/`some View`/`VStack`/`Text` come from `SwiftUI`; `AppViewModel` from `SingleThreadCore`. No `EventKit` import needed.

#### 2. Delete the extension block from `SingleThread/ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete from the `// MARK: - Notifications (iOS)` comment through the matching `#endif` (the whole block that currently sits after the struct's closing `}`). The file now ends after the struct's closing brace.

#### 3. Widen `appViewModel` access in `SingleThread/ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

The moved members read `appViewModel?.pendingSummary` / `lastScheduleSummary`. Change:

```swift
    #if os(iOS)
        private let appViewModel: AppViewModel?
    #endif
```
→
```swift
    #if os(iOS)
        let appViewModel: AppViewModel?
    #endif
```

(remove `private`; the `#if os(iOS)` wrapper stays).

### Verification
#### Automated
- [ ] `SIM='…' make build` succeeds
- [ ] `SIM='…' ./scripts/test.sh --unit-only` passes
- [ ] `make lint` returns 0

#### Manual
- [ ] `wc -l SingleThread/ContentView.swift` ≈ 687
- [ ] Optional: `SIM='…' ./scripts/test.sh --ui-only` — notification UI seams (`pendingStatus` / `lastScheduleStatus` under `--ui-testing-notifications`) still render (`NotificationSchedulingUITests` / `NotificationsUITests` pass)

---

## Phase 3: Settings-bag plumbing → `ContentView+Settings.swift`

Move `settingsSheetWritebacks` and `makeSettingsBag` out of the struct body. Only stage that reduces **both** counters (file → ~610, struct body 563 → ~488).

### Changes

#### 1. Create `SingleThread/ContentView+Settings.swift`
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: create

Content (members moved verbatim; `private func` → `func`):

```swift
import SingleThreadCore
import SwiftUI

extension ContentView {
    /// Builds the Settings sheet content. The write-back chain is split into
    /// staged values so each expression stays within the compiler's type-check
    /// budget (a single 17-modifier chain does not).
    func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View {
        let withAppearance = SettingsView(
            bindings: bag,
            backgroundImage: viewModel.backgroundImage,
            availableLists: viewModel.store.availableLists,
            excludedLists: excludedListsBinding,
            entitlementStore: viewModel.store.entitlementStore,
            viewModel: SettingsViewModel())
            // The bag is a plain in-memory holder; write each changed value
            // back to the @AppStorage-backed property so settings survive
            // relaunch (mirrors the old direct-bind behavior).
            .onChange(of: bag.appearanceMode) { _, new in appearanceMode = new }
            .onChange(of: bag.textSize) { _, new in textSize = new }
        #if os(iOS)
            let withIOSPreferences = withAppearance
                .onChange(of: bag.allowsLandscape) { _, new in allowsLandscape = new }
                .onChange(of: bag.enableActionButtons) { _, new in enableActionButtons = new }
                .onChange(of: bag.showSwipePrompt) { _, new in showSwipePrompt = new }
                .onChange(of: bag.showUndoButton) { _, new in showUndoButton = new }
                .onChange(of: bag.notificationsEnabled) { _, new in notificationsEnabled = new }
                .onChange(of: bag.notificationIntervalHours) { _, new in notificationIntervalHours = new }
        #else
            let withIOSPreferences = withAppearance
        #endif
        return withIOSPreferences
            .onChange(of: bag.showMicrophoneButton) { _, new in showMicrophoneButton = new }
            .onChange(of: bag.backgroundEnabled) { _, new in backgroundEnabled = new }
            .onChange(of: bag.backgroundFadePercent) { _, new in backgroundFadePercent = new }
            .onChange(of: bag.showUndatedReminders) { _, new in showUndatedReminders = new }
            .onChange(of: bag.sortOption) { _, new in sortOption = new }
            .onChange(of: bag.showDate) { _, new in showDate = new }
            .onChange(of: bag.showList) { _, new in showList = new }
            .onChange(of: bag.showRecurrence) { _, new in showRecurrence = new }
            .onChange(of: bag.showAlarms) { _, new in showAlarms = new }
            .onChange(of: bag.showCompletionGlow) { _, new in showCompletionGlow = new }
    }

    /// Builds a fresh bindings bag from the current `@AppStorage`-backed
    /// preference values.
    @MainActor
    func makeSettingsBag() -> SettingsBindings {
        #if os(iOS)
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                allowsLandscape: allowsLandscape,
                enableActionButtons: enableActionButtons,
                showSwipePrompt: showSwipePrompt,
                showUndoButton: showUndoButton,
                notificationsEnabled: notificationsEnabled,
                notificationIntervalHours: notificationIntervalHours,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #else
            SettingsBindings(
                appearanceMode: appearanceMode,
                textSize: textSize,
                showMicrophoneButton: showMicrophoneButton,
                backgroundEnabled: backgroundEnabled,
                backgroundFadePercent: backgroundFadePercent,
                backgroundPinned: backgroundPinned,
                showUndatedReminders: showUndatedReminders,
                sortOption: sortOption,
                showDate: showDate,
                showList: showList,
                showRecurrence: showRecurrence,
                showAlarms: showAlarms,
                showCompletionGlow: showCompletionGlow)
        #endif
    }
}
```

Keep the `#if os(iOS)` branches inside both functions verbatim. `@MainActor` stays on its own line above `makeSettingsBag`. `SettingsBindings`, `SettingsViewModel`, `BackgroundImageStore` come from `SingleThreadCore`; `SettingsView` is in the same app target (no import).

#### 2. Delete both functions from `SingleThread/ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete `private func settingsSheetWritebacks(_ bag: SettingsBindings) -> some View { … }` and `@MainActor private func makeSettingsBag() -> SettingsBindings { … }` (including their doc comments) from the struct body. `settingsSheetContent` (which stays) now calls the internal extension method `settingsSheetWritebacks(bag)`; `body`'s gear-button action calls `makeSettingsBag()` — both resolve to the extension.

#### 3. Widen access on the members the moved funcs read, in `SingleThread/ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Remove `private` from each of the following (they are read directly by the moved extension members):

- All 19 `@AppStorage` properties: `appearanceMode`, `textSize`, `allowsLandscape` (iOS), `showMicrophoneButton`, `backgroundEnabled`, `backgroundFadePercent`, `backgroundPinned`, `enableActionButtons` (iOS), `showSwipePrompt` (iOS), `showUndoButton` (iOS), `notificationsEnabled` (iOS), `notificationIntervalHours` (iOS), `showUndatedReminders`, `sortOption`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showCompletionGlow`
  - Example: `@AppStorage("appearanceMode")\n    private var appearanceMode = AppearanceMode.system` → `@AppStorage("appearanceMode")\n    var appearanceMode = AppearanceMode.system`
  - The `#if os(iOS)` wrappers and the `store: .standard` / `store: AppGroup.defaults` arguments stay unchanged.
- `private let viewModel: ContentViewModel` → `let viewModel: ContentViewModel`
- `private var excludedListsBinding: Binding<Set<String>>` → `var excludedListsBinding: Binding<Set<String>>`

Do **not** touch `@State` (`isShowingSettings`, `isShowingPurchase`, `settingsBag`), the three `@Environment` properties, `isGlowUITesting`, or `swipePromptBinding` — none are read by the moved functions.

### Verification
#### Automated
- [ ] `SIM='…' make build` succeeds
- [ ] `SIM='…' ./scripts/test.sh --unit-only` passes
- [ ] `make lint` returns 0

#### Manual
- [ ] `wc -l SingleThread/ContentView.swift` ≈ 610
- [ ] Sanity: `swiftlint lint --strict` reports no `type_body_length` for `ContentView` (the struct body is now < 500; the directive is still present this stage, so absence of a warning is expected regardless)

---

## Phase 4: Restore threshold + remove disables

The acceptance layer. Converts the measurement from "silenced" to "enforced".

### Changes

#### 1. `.swiftlint.yml` — restore threshold
**File**: `.swiftlint.yml`
**Action**: modify

```yaml
file_length:
  warning: 700
  error: 800
```
→
```yaml
file_length:
  warning: 650
  error: 800
```

#### 2. `SingleThread/ContentView.swift` — remove disables + stale comments, rewrite header
**File**: `SingleThread/ContentView.swift`
**Action**: modify

- Delete line 5 `// swiftlint:disable file_length`.
- Delete the stale block above the struct (`// The single-screen UI keeps every view modifier in one struct; the undo` / `// overlay pushes it just past 500 lines.`) and line 13 `// swiftlint:disable:next type_body_length`.
- Rewrite the header (lines 1–4) so it no longer claims the file sits *above* the thresholds:

```swift
// The single-screen UI concentrates its view modifiers in this struct, with
// non-view plumbing (settings bag, iOS notifications) and canvas previews
// decomposed into sibling `ContentView+*.swift` extension files so this file
// stays under the `file_length` (650) and `type_body_length` (500) thresholds.
```

Resulting top of file:

```swift
// The single-screen UI concentrates its view modifiers in this struct, with
// non-view plumbing (settings bag, iOS notifications) and canvas previews
// decomposed into sibling `ContentView+*.swift` extension files so this file
// stays under the `file_length` (650) and `type_body_length` (500) thresholds.
import EventKit
import SingleThreadCore
import Speech
import SwiftUI

struct ContentView: View {
```

### Verification
#### Automated
- [ ] `make lint` returns 0 — `swiftlint lint --strict` reports **0 violations across all 136 files** with **no** size disables on `ContentView`
- [ ] Full CI-identical gate `SIM='…' ./scripts/test.sh` passes (format, lint, build, watch build, Periphery, unit + UI + watch UI + macOS build/tests)

#### Manual
- [ ] `grep -n "swiftlint:disable" SingleThread/ContentView.swift` returns nothing (both directives gone)
- [ ] `wc -l SingleThread/ContentView.swift` ≈ 610 (under the 650 warning); the struct body is < 500 (under the `type_body_length` warning)

---

## Testing Checkpoints (resume points)

Each line is the gate that must be green before the next stage begins:

- **After Phase 1**: `SIM='…' make build && SIM='…' ./scripts/test.sh --unit-only && make lint` green; ContentView.swift ≈ 739 lines.
- **After Phase 2**: same three commands green; ContentView.swift ≈ 687 lines.
- **After Phase 3**: same three commands green; ContentView.swift ≈ 610 lines, struct body < 500.
- **After Phase 4**: `make lint` = 0 at 650 with no disables; full `SIM='…' ./scripts/test.sh` green.

## Cross-cutting notes

- **Access control**: the only non-layered change is `private` → `internal` widening on the 19 `@AppStorage` properties, `viewModel`, `excludedListsBinding` (Phase 3) and `appViewModel` (Phase 2). Each is listed explicitly in its phase and is caught at compile time at that stage.
- **No new tests**: this is pure code movement (design §6). The existing suites — `SingleThreadTests`, `MicrophoneToggleTests`, `SettingsViewTests`, and the notification UI tests — are the regression guard.
- **Out of scope (do not touch)**: `backgroundPinned`'s missing bag write-back (pre-existing bug); no new View structs; no `type_body_length`/`function_body_length` config changes; no extraction of `reminderList` or any other sub-view.
- **Commit discipline**: commit after each phase lands green (each stage is independently valuable; Stages 1–3 can land even if Stage 4 ever reds).
