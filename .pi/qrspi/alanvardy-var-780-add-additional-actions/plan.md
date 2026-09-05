# Implementation Plan

## Overview

Move `enableActionButtons` into `AppGroup.defaults` with watch sync, then build a toggle-gated 3-action menu (Skip / Reschedule / Delete) on iOS (confirmationDialog), macOS (Menu), and watch (confirmationDialog) — extracting the nudge sheet's DatePicker into a reusable `RescheduleSheet`. Toggle-off is behaviorally identical to today.

---

## Phase 1: Storage & Sync Foundation

Move `enableActionButtons` from `UserDefaults.standard` to `AppGroup.defaults`, add it to the watch-sync pipeline (PayloadKey + pushAll + apply(context:)), create the watch-side state holder. Update both test seams. **Zero UI changes** — toggle-off path is unchanged.

### Changes

#### 1. Add `enableActionButtons` to sync PayloadKey
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify — add new enum case + always insert in pushAll + decode in apply(context:) + new receive hook

Add to `PayloadKey` enum (after `entitled` at line `:293`):
```swift
static let enableActionButtons = "enableActionButtons"
```

In `pushAll()` (line `:183`, inside the always-present dictionary literal, after `PayloadKey.completionCount`):
```swift
PayloadKey.enableActionButtons: AppGroup.defaults.bool(forKey: "enableActionButtons"),
```

In `apply(context:)` (after `showCompletionGlow` block at `:370-373`):
```swift
if let enableActionButtons = context[PayloadKey.enableActionButtons] as? Bool {
    AppGroup.defaults.set(enableActionButtons, forKey: "enableActionButtons")
    let handler = onEnableActionButtonsReceived
    handler?(enableActionButtons)
}
```

Add new `nonisolated(unsafe)` hook property (alongside existing hooks, after `onEntitlementReceived` at `:145`):
```swift
/// Hook fired on the counterpart when the "enable action buttons" preference
/// arrives in an application context. Passes the received value. Same
/// write-once-before-activate / `nonisolated(unsafe)` rationale as
/// `onShowCompletionGlowReceived`.
public nonisolated(unsafe) var onEnableActionButtonsReceived: ((Bool) -> Void)?
```

#### 2. Create watch-side state holder
**File**: `SingleThreadWatch/ShowEnableActionButtonsState.swift` (new)
**Action**: create

```swift
import Foundation
import SwiftUI

/// Observable holder for the "enable action buttons" flag, received from the
/// phone via the sync pipeline. Reads its initial value from `.standard`
/// (which falls back to `AppGroup.defaults` on watchOS via `AppGroup.swift:20-22`).
/// Updates arrive through the sync pipeline's explicit `onEnableActionButtonsReceived` callback.
@Observable
final class ShowEnableActionButtonsState {
    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "enableActionButtons")
    }

    private(set) var isEnabled: Bool

    func apply(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "enableActionButtons")
        isEnabled = value
    }
}
```

#### 3. Wire watch-side state holder into WatchAppViewModel
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify

Add property (after `entitlementState` at `:70`):
```swift
let showEnableActionButtonsState: ShowEnableActionButtonsState
```

In `init` (after `entitlementState = EntitlementState()` at `:43`):
```swift
showEnableActionButtonsState = ShowEnableActionButtonsState()
```

In `reminderViewModel` lazy init, add after `entitlementState:` param:
```swift
showEnableActionButtonsState: showEnableActionButtonsState,
```

In `wireStateReceiveHooks` (after `entitlementState` block at `:248`):
```swift
let showEnableActionButtonsState = showEnableActionButtonsState
service.onEnableActionButtonsReceived = { [weak showEnableActionButtonsState] value in
    Task { @MainActor in showEnableActionButtonsState?.apply(value) }
}
```

#### 4. Add showEnableActionButtonsState to WatchReminderViewModel
**File**: `SingleThreadWatch/WatchReminderViewModel.swift`
**Action**: modify

Add to `init` parameter list (after `entitlementState:`):
```swift
showEnableActionButtonsState: ShowEnableActionButtonsState,
```

Add stored property (after `entitlementState` at `:42`):
```swift
let showEnableActionButtonsState: ShowEnableActionButtonsState
```

In `init` body:
```swift
self.showEnableActionButtonsState = showEnableActionButtonsState
```

#### 5. Move iOS-side @AppStorage to AppGroup.defaults
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Change line `:96-97` from:
```swift
@AppStorage("enableActionButtons")
var enableActionButtons = false
```
To:
```swift
@AppStorage("enableActionButtons", store: AppGroup.defaults)
var enableActionButtons = false
```

#### 6. Update ContentViewModel.showsActionButtons to read from AppGroup
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify — change `UserDefaults.standard` → `AppGroup.defaults` at line `:56`

```swift
AppGroup.defaults.bool(forKey: "enableActionButtons")
```

#### 7. Update both iOS test seams to write to AppGroup.defaults
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — two call sites

In `makeStore` (line `:291`), change `UserDefaults.standard.set(true, forKey: "enableActionButtons")` → `AppGroup.defaults.set(true, forKey: "enableActionButtons")`.

In `seededStore` (line `:350`), same change.

#### 8. Add enableActionButtons to handlePreferencesChanged diff set
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify (lines `:432-457`)

Add variable before the `if`:
```swift
let currentEnableActionButtons = AppGroup.defaults.bool(forKey: "enableActionButtons")
```

Add to the diff `if` clause:
```swift
|| currentEnableActionButtons != lastEnableActionButtons
```

Add to assignment block:
```swift
lastEnableActionButtons = currentEnableActionButtons
```

Add cache property (after `lastShowCompletionGlow`):
```swift
private var lastEnableActionButtons = AppGroup.defaults.bool(forKey: "enableActionButtons")
```

#### 9. Verify UITestingSeed reset already includes key
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: verify — the key `"enableActionButtons"` is already in the reset list at `:86`. Verify the string matches exactly. No change needed.

#### 10. SettingsBindings writeback — no change needed
**File**: `SingleThread/ContentView+Settings.swift`
**Action**: verify — the `enableActionButtons` binding is already in the `settingsSheetWritebacks` chain at `:9-46`. The `@AppStorage` change in step 5 handles persistence.

#### 11. Toggle migration (one-shot: .standard → AppGroup)
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — add in `AppViewModel.init` after `Self.registerDefaults()` at `:27`

```swift
// Migrate enableActionButtons from .standard to AppGroup.defaults (one-shot).
if UserDefaults.standard.object(forKey: "enableActionButtons") != nil,
   AppGroup.defaults.object(forKey: "enableActionButtons") == nil {
    AppGroup.defaults.set(UserDefaults.standard.bool(forKey: "enableActionButtons"),
                          forKey: "enableActionButtons")
}
```

### Verification

#### Automated
- [ ] `make build` compiles clean (iOS + watch targets)
- [ ] `make test` (unit suite) passes — new tests + all 552 existing
- [ ] `make watch-build` compiles clean

#### New Unit Tests
- [ ] `ShowEnableActionButtonsPreferenceTests.swift`: nil-key reads `false` (default-off), `set(true)`/`set(false)` round-trip, serialized to `.standard`
- [ ] `SkippedReminderSyncServiceTests.swift`: push context includes `enableActionButtons` key + value; receive decodes it and fires hook
- [ ] `WatchSyncPipelineTests.swift`: `apply(context:)` with the new key persists to `.standard`; absent key is a no-op

#### Existing Must Stay Green
- [ ] `ActionButtonTests.swift` (reads toggle — now from AppGroup)
- [ ] All 552 unit tests pass

#### Manual
- [ ] Toggle ON in Settings → relaunch → toggle still ON (persists via AppGroup)
- [ ] Fresh install (no key set) → toggle OFF by default
- [ ] Migration: pre-set `.standard` key to `true` only → launch → toggle ON in UI

---

## Phase 2: Store Methods & Gate Logic

Add the watch→phone reschedule relay method on `SkippedReminderSyncService`, wire the phone-side receive handler, add `onRescheduleReminder` hook to `ReminderStore` for watch relay, and create a pure `ActionMenuGate` function.

### Changes

#### 1. Add reschedule relay PayloadKey + sendMessage method
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

Add to `PayloadKey` enum (after `deleteReminderIdentifier` at `:284`):
```swift
static let rescheduleReminderIdentifier = "rescheduleReminderIdentifier"
```

Add new public method (after `requestDeleteReminder` at `:237`):
```swift
public func requestRescheduleReminder(identifier: String, dueDateComponents: DateComponents) {
    var payload: [String: Any] = [PayloadKey.rescheduleReminderIdentifier: identifier]
    var dc: [String: Any] = [:]
    if let year = dueDateComponents.year { dc["year"] = year }
    if let month = dueDateComponents.month { dc["month"] = month }
    if let day = dueDateComponents.day { dc["day"] = day }
    if let hour = dueDateComponents.hour { dc["hour"] = hour }
    if let minute = dueDateComponents.minute { dc["minute"] = minute }
    payload["dueDateComponents"] = dc
    session.sendMessage(payload, replyHandler: nil) { error in
        Self.logger.error("Failed to send reschedule request: \(error.localizedDescription, privacy: .public)")
    }
}
```

Add receive-side decoding in `session(_:didReceiveMessage:)` (after `deleteReminderIdentifier` block at `:251`):
```swift
if let identifier = message[PayloadKey.rescheduleReminderIdentifier] as? String,
   let dcDict = message["dueDateComponents"] as? [String: Int] {
    var components = DateComponents()
    components.year = dcDict["year"]
    components.month = dcDict["month"]
    components.day = dcDict["day"]
    components.hour = dcDict["hour"]
    components.minute = dcDict["minute"]
    let handler = onRescheduleReminderReceived
    handler?(identifier, components)
}
```

Add new hook property (alongside `onDeleteReminderReceived`):
```swift
public nonisolated(unsafe) var onRescheduleReminderReceived: ((String, DateComponents) -> Void)?
```

#### 2. Add onRescheduleReminder hook to ReminderStore (for watch relay)
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Add hook property (alongside `onDeleteReminder` at `:105`):
```swift
public var onRescheduleReminder: ((String, DateComponents) -> Void)?
```

Modify watchOS branch of `rescheduleReminder(identifier:to:)` (lines `:350-352`):
```swift
#if os(watchOS)
    let handler = onRescheduleReminder
    handler?(identifier, due)
    return true
#endif
```

#### 3. Wire phone-side reschedule handler in AppViewModel
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify — add after `onDeleteReminderReceived` handler at `:49-51`

```swift
service.onRescheduleReminderReceived = { [eak store] identifier, components in
    Task { await store?.rescheduleReminder(identifier: identifier, to: components) }
}
```

#### 4. Wire watch-side reschedule hook in WatchAppViewModel
**File**: `SingleThreadWatch/WatchAppViewModel.swift`
**Action**: modify — add alongside `store.onDeleteReminder` at `:214`

```swift
store.onRescheduleReminder = { identifier, components in
    service.requestRescheduleReminder(identifier: identifier, dueDateComponents: components)
}
```

#### 5. Create ActionMenuGate
**File**: `SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift` (new)
**Action**: create

```swift
import Foundation

public enum ActionMenuGate {
    public static func showsActionMenu(
        enableActionButtons: Bool,
        canMutate: Bool,
        hasVisibleReminder: Bool
    ) -> Bool {
        enableActionButtons && canMutate && hasVisibleReminder
    }
}
```

### Verification

#### Automated
- [ ] `make build` compiles clean
- [ ] `make test` passes

#### New Unit Tests
- [ ] `ActionMenuGateTests.swift`: 2×2×2 table — toggle on/off × canMutate true/false × hasReminder true/false
- [ ] `SkippedReminderSyncServiceTests` additions: `requestRescheduleReminderSendsMessage`, `receiveRescheduleReminder`
- [ ] `EventKitStoringTests.reschedule` suite stays green
- [ ] `ReminderStoreWatchTests` updated for `onRescheduleReminder` hook

---

## Phase 3: Extract RescheduleSheet

Extract the nudge sheet's DatePicker + eschedule logic into a standalone `RescheduleSheet` view.
Design: `RescheduleSheet` is a plain View (no NavigationStack — callers wrap it).
It provides: optional nudge message, DatePicker (date-only vs date+time), Reschedule confirm button.
Callers provide Cancel in their own toolbar + any extra buttons.

### Canges

#### 1. Create RescheduleSheet view
**File**: `SingleThread/RescheduleSheet.swift` (new)
**Action**: create

```swift
import EventKit
import SwiftUI

struct RescheduleSheet: View {
    let reminder: EKReminder?
    let onReschedule: (DateComponents) async -> Bool
    let onCancel: () -> Void
    let nudgeMessage: String?

    @State private var date: Date = Date().addingTimeInterval(86_400)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let nudgeMessage {
                Text(nudgeMessage)
                    .font(.headline)
                    .accessibilityIdentifier("nudgeSheetTitle")
            }

            DatePicker(
                "Reschedule to",
                selection: $date,
                displayedComponents: hasDueTime ? [.ate, .hourAndMinute] : [.ate])
                .accessibilityIdentifier("rescheduleDatePicker")

            HStack {
                Spacer()
                Button {
                    let components = Calendar.current.dateComponents(
                        hasDueTime ? [.ear, .month, .day, .hour, .minute] : [.year, .month, .day],
                        from: date)
                    Task { if await onReschedule(components) { onCancel() } }
                } label: {
                    Label("Reschedule", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("rescheduleConfirmButton")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hasDueTime: Bool {
        guard let reminder, let components = reminder.dueDateComponents else { return false }
        return components.hour != nil
    }
}
```

#### 2. Refactor nudge sheet to use RescheduleSheet
**File**: `SingleThread/ContentView+iOS.swift`
**Action**: modify

Replace `nudgeSheetContent` body (lines `:59-86`) with:
```swift
var nudgeSheetContent: some View {
    avigationStack {
        VStack(alignment: .leading, spacing: 16) {
            RescheduleSheet(
                reminder: nudgedReminder,
                onReschedule: { [weak viewModel] components in
                    guard let viewModel else { return false }
                    return await viewModel.rescheduleNudgedReminder(to: components)
                },
                onCancel: { isShowingNudgeSheet = false },
                nudgeMessage: "This reminder keeps coming back.")
            nudgeViewInRemindersButton
            nudgeDeleteButton
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cance") { isShowingNudgeSheet = false }
            }
        }
    }
}
```

Add helper for the nudged reminder:
```swift
private var nudgedReminder: EKReminder? {
    guard let identifier = viewModel.nudgeIdentifier else { return nil }
    return viewModel.store.visibleReminders.first { $0.calendarItemIdentifier = identifier }
}
```

Remove `nudgedReminderHasDueTime` (lines `:91-101`) and `nudgeRescheduleButton` (lines `:107-122`) — logic moved into `RescheduleSheet`.

#### 3. Add general reschedule method to ContentViewModel
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify — add (if not present)

```swift
func rescheduleReminder(identifier: String, to components: DateComponents) async -> Bool {
    await store.rescheduleReminder(identifier: identifier, to: components)
}
```

(Verify `rescheduleNudgedReminder` at `:205-212` only does nudge-specifc cleanup; if so, keep it and add this general one.)

### Verifcation

#### Automated
- [ ] `make build` complies
- [ ] `make test` + `make ui-test` pass
- [ ] `SkipNudgeUITests.swift` — nudge flow unchanged, `nudgeRescheduleButton` id → `rescheduleConfirmButton` id
- [ ] `SkipNudgeUITests.swift` — update selectors if ids changed

#### New Tests
- [ ] `RescheduleSheetTests.swift`: verify `displayedComponents` logic — date-only reminder → `.date`, timed → `[.date, .hourAndMinute]`

---

## Phase 4: Platform Action Menus

Build the toggle-gated action menu on each platform. All share `ActionMenuGate` (Phase 2) and `RescheduleSheet` (Phase 3). **Toggle-off path is behaviorally identical to today.**

### Phase 4a: iOS — confirmationDialog

#### Chages

##### 1. Add state flags and confirmationDialog to skipButton
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add `@State` properties alongside other state (near `isShowingNudgeSheet`):
```swift
@State private var isShowingActionMenu = false
@State private var isShowingRescheduleSheet = false
@State private var actionMenuReminder: EKReminder?
```

Add computed gate (in the `#if osiOS)` section):
```swift
private var showActionMenu: Bool {
    ActionMenuGate.showsActionMenu(
        enableActionButtons: enableActionButtons,
        canMutate: viewModel.store.canMutate,
        hasVisibleReminder: viewModel.store.visibleReminders.first != nil)
}
```

Modify `skipButton` in `actionCluster` (lines `:526-536`):
```swift
private var skipButton: some View {
    Button {
        if showActionMenu {
            actionMenuReminder = viewModel.store.visibleReminders.first
            isShowingActionMenu = true
        } else {
            viewModel.skipCurrentReminder()
        }
    } label: {
        Label(SharedStrings.skipAction, systemImage: "circle.slash")
            .labelStyle(.iconOnly)
            .controlPlate()
    }
    .accessibilityLabel(SharedStrings.skipReminderAccessibility)
    .accessibilityIdentifier("skipButton")
    .accessibilityAddTraits(.isButton)
    .confirmationDialog("Reminder", isPresented: $isShowingActionMenu) {
        Button(SharedStrings.skipAction) { viewModel.skipCurrentReminder() }
        Button("Reschedule") { isShowingRescheduleSheet = true }
            .accessibilityIdentifier("rescheduleButton")
        Button(SharedStrings.deleteAction, role: .destructive) {
            Task { await viewModel.deleteCurrentReminder() } }
            .accessibilityIdentifier("deleteButton")
    }
}
```

Add `.sheet` modifier for reschedule (alongside other sheets at `:267-278`):
```swift
.sheet(isPresented: $isShowingRescheduleSheet) {
    avigationStack {
        RescheduleSheet(
            reminder: actionMenuReminder,
            onReschedule: { [weak viewModel] components in
                guard let viewModel, let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier
                else { return false }
                return await viewModel.store.rescheduleReminder(identifier: id, to: components)
            },
            onCancel: { isShowingRescheduleSheet = false },
            nudgeMessage: nil)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cance") { isShowingRescheduleSheet = false }
            }
        }
    }
}
```

### Phase 4b: macOS — Menu

#### Chages

##### 1. Conditional Menu vs Button for skip; hide Delete when toggle ON
**File**: `SingleThread/ContentView.swift`
**Action**: modify — replace macOS `actionButtons` (lines `:328-377`)

```swift
#if os(macOS)
    private var actionButtons: some View {
        let showMenu = ActionMenuGate.showsActionMenu(
            enableActionButtons: enableActionButtons,
            canMutate: viewModel.store.canMutate,
            hasVisibleReminder: viewModel.store.visibleReminders.first != nil)

        HSack(spacing: 32) {
            // Complete — unchanged
            Button {
                Task { await viewModel.completeCurrentReminder() }            } label: {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
            }
            .tint(.green)
            .keyboardShortcut("c", modifiers: [])
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)

            if showMenu {
                Menu {
                    Button(SharedStrings.skipAction) { viewModel.skipCurrentReminder() }
                    Button("Reschedule") { isShowingRescheduleSheet = true }
                        .accessibilityIdentifier("rescheduleButton")
                    Button(SharedStrings.deleteAction, role: .destructive) {
                        Task { await viewModel.deleteCurrentReminder() } }
                        .accessibilityIdentifier("deleteButton")
                        .keyboardShortcut(.delete, modifiers: [])
                } label: {
                    Label(SharedStrings.skipAction, systemImage: "circle.slash")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.orange)
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel(SharedStrings.skipReminderAccessibility)
                .accessibilityIdentifier("skipButton")
                .accessibilityAddTraits(.isButton)
            } else {
                // Original skip button
                Button {
                    viewModel.skipCurrentReminder()
                } label: {
                    Label(SharedStrings.skipAction, systemImage: "circle.slash")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.orange)
                .keyboardShortcut("s", modifiers: [])
                .accessibilityLabel(SharedStrings.skipReminderAccessibility)
                .accessibilityIdentifier("skipButton")
                .accessibilityAddTraits(.isButton)

                // Standalone Delete — only when toggle OFF
                Button {
                    Task { await viewModel.deleteCurrentReminder() }                } label: {
                    Label(SharedStrings.deleteAction, systemImage: "trash")
                        .labelStyle(.iconOnly)
                        .font(.title)
                }
                .tint(.red)
                .accessibilityLabel(SharedStrings.deleteReminderAccessibility)
                .accessibilityIdentifier("deleteButton")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.bottom, 8)
    }

    @State private var isShowingRescheduleSheet = false
#endif
```

Also add `.sheet` modifier on macOS (share with iOS pattern). If `#if os(iOS)` gates the iOS `isShowingRescheduleSheet` property, add a macOS one:
```swift
#if os(macOS)
    @State private var isShowingRescheduleSheet = false
#endif
```

### Phase4c: watch — confirmationDialog + Reschedule Relay

#### Canges

##### 1. Gate watch skip button with confirmationDialog
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Add to `WatchReminderViewModel`:
```swift
var isShowingActionMenu = false
var isShowingRescheduleSheet = false
var rescheduleDate = Date().addingTimeInterval(86_400)
```

Modify skip button in `actionButtons` (`WatchReminderView.swift:130-139`):
```swift
let canShowMenu = viewModel.showEnableActionButtonsState.isEnabled
    && viewModel.store.canMutate
    && viewModel.store.visibleReminders.first != nil

Button {
    if canShowMenu {
        viewModel.isShowingActionMenu = true
    } else {
        viewModel.store.skipCurrentReminder()
    }
} label: {
    Label(SharedStrings.skipAction, systemImage: "circle.slash")
        .labelStyle(.iconOnly)
}
.tint(.orange)
.accessibilityLabel(SharedStrings.skipReminderAccessibility)
.accessibilityIdentifier("skipButton")
.accessibilityAddTraits(.isButton)
.confirmationDialog("Reminder", isPresented: $viewModel.isShowingActionMenu) {
    Button(SharedStrings.skipAction) { viewModel.store.skipCurrentReminder() }
    Button("Reschedule") { viewModel.isShowingRescheduleSheet = true }
    Button(SharedStrings.deleteAction, role: .destructive) {
        Task { await viewModel.store.deleteCurrentReminder() } }
}
```

Add `.sheet` modifier for reschedule (on the `actionButtons` or the skip button):
```swift
.sheet(isPresented: $viewModel.isShowingRescheduleSheet) {
    avigationStack {
        VStack {
            DatePicker("Reschedule to", selection: $viewModel.rescheduleDate, displayedComponents: [.date])
            Button("Reschedule") {
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day], from: viewModel.rescheduleDate)
                if let id = viewModel.store.visibleReminders.first?.calendarItemIdentifier {
                    await viewModel.store.rescheduleReminder(identifier: id, to: components)
                }
                viewModel.isShowingRescheduleSheet = false
            }
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cance") { viewModel.isShowingRescheduleSheet = false }
            }
        }
    }
}
```

Calling `store.rescheduleReminder` on watchOS fires the `onRescheduleReminder` hook wired in Phase 2 → `requestRescheduleReminder` relay to phone. The store method returns `true` on watchOS after firing the hook.

### Phase 4 Verification

#### Automated
- [ ] `make build` compiles (iOS + macOS + watch)
- [ ] `make test` passes — all unit tests including new gate tests
- [ ] `make ui-test` passes — iOS UI tests including new action-menu tests
- [ ] `make watch-ui-test` passes — watch UI tests including menu flow

#### New iOS UI Tests (extend `ActionButtonsUITests.swift` or new `ActionMenuUITests.swift`)
- [ ] Seed toggle ON → tap skip → confirmationDialog appears → tap Skip → advances; tap Reschedule → sheet → pick → escheduled; tap Delete → removed
- [ ] Toggle OFF → tap skip → direct skip (existing behavior)
- [ ] `assertTogglePersists` pattern across elaunch

#### New Watch UI Tests (extend `SingleThreadWatchUITestsFlows.swift`)
- [ ] Seed toggle synced ON → tap skip → dialog appears by label → Skip advances; Delete removes; Reschedule → DatePicker sheet → confirm

#### Existing Must Stay Green
- [ ] `ActionButtonsUITests.swift` — cluster renders + skip advances
- [ ] `SkipNudgeUITests.swift` — nudge flow unchanged
- [ ] All other existing UI tests

#### Manual
- [ ] iOS: toggle ON → confirmationDialog → each action works
- [ ] iOS: toggle OFF → direct skip (no dialog)
- [ ] macOS: toggle ON → skip is a Menu → Delete hidden → keyboard shortcut 's' opens menu
- [ ] macOS: toggle OFF → skip + Delete as before
- [ ] watch: toggle ON + phone paired → skip → dialog → each action works
- [ ] watch: toggle OFF → direct skip

---

## File Budget Checks

- `ContentView.swift` at 716 lines (budget 650/800). Adding ~20 lines (iOS) + ~30 (macOS) + ~4 (state) → ~770 — under 800. If exceeds 800, split action-menu code into `ContentView+ActionMenu.swift` with standard header.
- `ContentView+iOS.swift` at 157 lines. After RescheduleSheet extraction: shrinks ~40 lines, adds ~10 lines → net eduction.
- `WatchReminderView.swift` — adding ~40 lines for confirmationDialog + sheet. Check urrent length; consider `WatchReminderView+ActionMenu.swift` extension if close to budget.

---

## Testig Checkpoints

| Stage | Checkpoint |
|---|---|
| 1 | `make build` + `make watch-build`; `make test` — all unit tests + new preference/sync tests |
| 2 | `make build`; `make test` — store + gate logic tests |
| 3 | `make test` + `make ui-test` — nudge flow unchanged |
| 4 | `make test` + `make ui-test` + `make watch-ui-test` — all platforms |
| Final | `./scripts/test.sh` — full CI gate (format, lint, periphery, unit, UI, watch) |