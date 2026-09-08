# Q5: Multi-option action-presentation patterns and platform constraints

All claims verified by reading the cited lines. Deployment targets (project.pbxproj): iOS 18.7 (project.pbxproj:765), macOS 26.5 (:768), watchOS 26.5 (:965).

## 1. confirmationDialog - watchOS only, exactly 2 call sites

Both sit in SingleThreadWatch/WatchReminderView.swift, both driven by plain `var` booleans on the observable view model (not `@State`):

1. **Card tap -> Refresh/Delete dialog** (2 actions):
   - `WatchReminderView.swift:214-215` - `.onTapGesture { viewModel.isShowingRefreshConfirmation = true }` on the reminder `ScrollView`; the tap target gets `.accessibilityAddTraits(.isButton)` (`:217`).
   - `WatchReminderView.swift:218-228` - `.confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation)`: `Button("Refresh")` (`:219-222`, id `refreshButton` at `:222`) and `Button(SharedStrings.deleteAction, role: .destructive)` (`:224-227`, id `deleteButton` at `:227`).
   - Binding works via local `@Bindable var viewModel` inside `reminderCard` (declared ~`:203`).
   - State flag: `WatchReminderViewModel.swift:47 var isShowingRefreshConfirmation = false`.
2. **Nudge banner -> Delete-only dialog** (1 action):
   - `WatchReminderView.swift:231-232` - banner `Button` sets `viewModel.isShowingNudgeDialog = true`; banner id `skipNudgeBanner` (`:237`).
   - `WatchReminderView.swift:238-243` - `.confirmationDialog(SharedStrings.skipNudgeTitle, isPresented: $viewModel.isShowingNudgeDialog)`: single `Button(SharedStrings.deleteAction, role: .destructive)` (`:239-242`, id `nudgeDeleteButton` at `:242`).
   - State flag: `WatchReminderViewModel.swift:55 var isShowingNudgeDialog = false`.

The watch target contains **no sheets, menus, pickers, alerts, or swipe actions** anywhere else (rg across `SingleThreadWatch/` finds only these two `confirmationDialog` hits). `SingleThreadWatchApp.swift` is a bare `WindowGroup` with no scene-level commands.


## 2. contextMenu - iOS only, 1 call site

- `SingleThread/ContentView.swift:451-471` - `.contextMenu` on the reminder card row, wrapped in `#if os(iOS)` (`:451`, `#endif` `:471`). Contains **2 actions**:
  - "View in Reminders" (deep link via `viewModel.openInReminders(reminder)`, `:453-459`) - label only, **no accessibility identifier** (tests match the label).
  - Delete: `Button` calling `viewModel.deleteCurrentReminder()` with `Label(SharedStrings.deleteAction, systemImage: "trash")`, `.accessibilityLabel(SharedStrings.deleteReminderAccessibility)`, `.accessibilityIdentifier("deleteButton")`, `.tint(.red)` (`:460-469`).
- Context-menu buttons do **not** use `Button(role: .destructive)`; destructive styling is `.tint(.red)` (`:469`).

## 3. swipeActions - iOS list rows (not explicitly gated)

- `SingleThread/ContentView.swift:472-489` - on the same reminder row as the contextMenu: `.swipeActions(edge: .leading)` with Complete (`:472-479`, `.tint(.green)`) and `.swipeActions(edge: .trailing)` with Skip (`:480-487`, `.tint(.orange)`). Neither button has an accessibility identifier; tests match labels ("Complete"/"Skip"). The row lives in a shared `List` (macOS uses the same `reminderList`), but swipe actions are inert on macOS; macOS gets its own action row instead (see section 6).

## 4. Sheets - iOS (3 sites; settings sheet shared with macOS)

All three attached in `ContentView` body:

- `ContentView.swift:267` - `.sheet(isPresented: $isShowingSettings) { settingsSheetContent }` (settings; present on iOS **and** macOS - not gated; macOS content gets `.frame(minWidth: 400, minHeight: 500)` at `ContentView.swift:602-605` so the List does not collapse to 0px). Flag: `@State private var isShowingSettings` (`:294`); a settings bag is rebuilt per presentation (`:261-265`).
- `ContentView.swift:270` - `.sheet(isPresented: $isShowingPurchase) { PurchaseSheet(...) }` (freemium upgrade). Flag: `@State private var isShowingPurchase` (`:298`).
- `ContentView.swift:275-289` - `#if os(iOS)` gate containing `.sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() }) { nudgeSheetContent }` (`:276`) plus the URL-spy overlay. Flag: `@State var isShowingNudgeSheet = false` (`:137`), set by the in-card nudge callback `ContentView.swift:429`.

**Nudge sheet (the repos only 3-action surface):** `SingleThread/ContentView+iOS.swift` (entire file gated `#if os(iOS)`, `:8`):
- `:66-91` - `nudgeSheetContent`: `NavigationStack` with title `nudgeSheetTitle` (`:72-73`), a `DatePicker` (`:75-77`), and three action buttons + a toolbar Cancel (`:79-86`).
- `:92-115` - `nudgeRescheduleButton` (id `nudgeRescheduleButton`).
- `:116-130` - `nudgeViewInRemindersButton` (id `nudgeViewInRemindersButton`) and `nudgeDeleteButton` (`:120-129`) - the nudge Delete is the **only `Button(role: .destructive)` on iOS**, with id `nudgeDeleteButton` (`:128`).


## 5. Picker / Menu usage

- Zero `Menu(` in any source target (rg over all 6 targets: only `.contextMenu` hits; no toolbar menus, no `CommandMenu`).
- `Picker` used **only inside settings sheets** (all in `SingleThread/`, never watch/widget):
  - `FilterSortSettingsView.swift:20` - sort picker, no explicit style.
  - `InterfaceSettingsView.swift:35` - appearance picker, id `appearancePicker`; `InterfaceSettingsView.swift:47` - text-size picker, id `textSizePicker`.
  - `NotificationsSettingsView.swift:24-35` - interval picker with **`.pickerStyle(.menu)`** (`:34`), id `notificationIntervalPicker`.
  - `BackgroundSettingsView.swift:31-41` - background-fade picker (percent options), id `backgroundFadePicker`.
- `DatePicker` appears once: `ContentView+iOS.swift:66` (nudge sheet reschedule).
- Tests treat headless pickers as **buttons**: `app.buttons["appearancePicker"].firstMatch` (`SingleThreadUITests/SingleThreadUITestsAppearanceLaunchTests.swift:71`) and `app.buttons["notificationIntervalPicker"].firstMatch` (`NotificationsUITests.swift:11`); options asserted **by label** like "24 hours" (`NotificationsUITests.swift:39-40`).

## 6. macOS pattern

- No `contextMenu`, no `confirmationDialog`, no `Menu`, no `Picker`-for-actions on macOS. Actions are **plain buttons in a bottom-bar HStack** - `#if os(macOS) actionButtons` at `ContentView.swift:328-371` (rendered inside `bottomBar` under another `#if os(macOS)` at `:657-662`): Complete `.tint(.green)` + `.keyboardShortcut("c", modifiers: [])` (`:330-344`), Skip `.tint(.orange)` + `.keyboardShortcut("s", modifiers: [])` (`:346-358`), Delete `.tint(.red)` with no shortcut (`:360-369`); each with `accessibilityLabel` + identifiers `completeButton`/`skipButton`/`deleteButton`.
- The only macOS modal is the shared settings sheet (section 4). So: **no multi-option single-control affordance exists on macOS today** - macOS actions are three always-visible buttons.

## 7. Widget

- `SingleThreadWidget/NextThingWidget.swift:141-158` - `actionButtons` HStack of two `Button(intent: CompleteReminderIntent())` / `Button(intent: SkipReminderIntent())` with `.tint(.green)`/`.tint(.orange)`, `.buttonStyle(.bordered)`, ids `completeButton`/`skipButton`. No presentation APIs at all.


## 8. How tests interact with these surfaces (labels vs identifiers)

**watchOS confirmationDialog - matched by LABEL, not identifier** (explicitly documented in three test comments):
- `SingleThreadWatchUITests/SingleThreadWatchUITests.swift:20-24` - `title.tap()` reveals dialog; `let refresh = app.buttons["Refresh"]` with comment "watchOS confirmation-dialog actions expose their label, not the SwiftUI accessibility identifier".
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift:123-131` - nudge dialog Delete: `app.buttons["Delete"]` with comment "watchOS dialog actions expose their label, not the identifier, so match the destructive Delete action by its label".
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift:144-150` - card-tap dialog Delete: `app.buttons["Delete"]` with the same comment style.
- Trigger is the card static-text label (`app.staticTexts["Buy groceries"].tap()`), not the `deleteButton`/`refreshButton` identifiers that exist on the dialog buttons in source (`WatchReminderView.swift:222,227,242`) - those identifiers are unreachable from watch XCUITest inside dialogs.

**iOS contextMenu - identifier + label mixed:** long-press `app.staticTexts["Buy groceries"].press(forDuration: 1.0)` (`SingleThreadUITestsFlows.swift:169,189`); Delete matched by **identifier** `app.buttons["deleteButton"]` (`:172-173`); "View in Reminders" matched by **label** (`:191`).

**iOS swipeActions - label only:** `swipeLeft()`/`swipeRight()` then `app.buttons["Skip"]` / `app.buttons["Complete"]` (`SingleThreadUITestsFlows.swift:63,91,122-130,154`; `SkipNudgeUITests.swift:32-38`).

**iOS nudge sheet - identifiers work normally:** `app.buttons["nudgeDeleteButton"]` / `"nudgeRescheduleButton"` / `"nudgeViewInRemindersButton"` (`SkipNudgeUITests.swift:41-49,72-79,104-115`).

**Accessibility audit:** `SingleThreadWatchUITests.swift:36-46` runs `performAccessibilityAudit` on watch for `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]` (no dialog interaction involved).

## 9. Strings and destructive-role styling

- Shared action strings live in `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:12-22` (`completeAction`="Complete", `skipAction`="Skip", `deleteAction`="Delete"); nudge dialog title is `SharedStrings.skipNudgeTitle` ("Skipped 6 times", `:24-27`); accessibility strings `completeReminderAccessibility`/`skipReminderAccessibility`/`deleteReminderAccessibility` at `:29-39`. The main watch dialog title "Reminder" is a raw literal (`WatchReminderView.swift:218`).
- Destructive styling per platform: watch dialogs use `role: .destructive` (`WatchReminderView.swift:224,239`); iOS nudge sheet uses `role: .destructive` (`ContentView+iOS.swift:120`); iOS contextMenu cannot use role, so `.tint(.red)` (`ContentView.swift:469`); macOS/iOS button rows use `.tint(.red)` (`ContentView.swift:364`).

## 10. Constraints relevant to presenting 2-3 actions from one control

1. **watchOS**: the only working multi-action affordance in this repo is `confirmationDialog`. It is the repos sole watch modal and the only place where **dialog actions are addressed by label in tests** (system suppresses SwiftUI identifiers inside the dialog on watch). The trigger is a plain single tap (`.onTapGesture`), exposed as a button trait via `.accessibilityAddTraits(.isButton)`. watchOS has no swipe/context-menu/sheet precedent in this codebase.
2. **iOS**: three coexisting affordances on one card row - long-press `contextMenu` (2 actions, identifiers reachable), swipe actions (labels only), and sheets (identifiers). The nudge sheet is the only 3-action surface; sheet Delete uses `role: .destructive`, context-menu Delete uses `.tint(.red)`.
3. **macOS**: no single-control multi-action pattern exists; actions are three always-visible bar buttons with keyboard shortcuts. A macOS action menu would have **no in-repo precedent**.
4. Widget/watch action clusters both use plain two-button HStacks, not menus.
5. Deployment targets are modern (iOS 18.7 / macOS 26.5 / watchOS 26.5), so no version-gating is observed; the per-platform split is a deliberate convention (`#if os(iOS)` for contextMenu/nudge sheet, `#if os(macOS)` for the action bar), not a deployment-target limitation.

