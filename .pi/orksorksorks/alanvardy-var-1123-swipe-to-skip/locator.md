# Locator: swipe actions, action menus, Skip reveal, enableActionButtons

## 1. Shared ActionMenuGate (SingleThreadCore)
- SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:7 - public enum; showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:) -> Bool = AND of all three. Pure; no per-platform branches.
- Consumers:
  - iOS SingleThread/ContentView+ActionMenu.swift:15-23 - showActionMenu (private) gates dialog.
  - macOS SingleThread/ContentView+ActionMenu.swift:92-98 - macShowActionMenu gates cluster.
  - watchOS SingleThreadWatch/WatchReminderView.swift:113-117 - canShowActionMenu reimplements the same AND inline (does NOT call the enum).

## 2. Swipe gesture + Skip reveal label
- SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift:4-41 - SwipeGestureOutcome (complete|skip|none), SwipeGesture.releaseDistance (72pt), outcome(for:), revealedOutcome(forOffset:). Pure logic.
- SingleThread/SwipeToActModifier.swift:
  - SwipeRevealPanel.presentation (lines ~57-76): reveals SharedStrings.completeAction / SharedStrings.skipAction + SF Symbols checkmark.circle.fill / circle.slash. Skip shown when traveling left.
  - SwipeToActModifier: DragGesture + .accessibilityAction(named: Skip/Complete).
  - .swipeToAct extension at SwipeToActModifier.swift:142.
- Attached at SingleThread/ContentView.swift:459 .swipeToAct { outcome in ... } (complete->completeCurrentReminder, skip->skipCurrentReminder).
- iOS context menu (long-press) Delete fallback: SingleThread/ContentView.swift:507-528 .contextMenu ("View in Reminders" + SharedStrings.deleteAction, id deleteButton).

## 3. enableActionButtons toggle gating
- Storage: SingleThread/ContentView.swift:100-101 @AppStorage("enableActionButtons", store: AppGroup.defaults) default true; mirrored in SingleThread/ContentViewModel.swift:77.
- Gate center: SingleThread/ContentViewModel.swift:80-97 - showsActionButtons = enableActionButtons && hasLoadedReminders && visible != nil.
- Migration: SingleThread/AppViewModel.swift:141-145 (UserDefaults->AppGroup), reset-to-ON at :273, :367; read at :594, :635.
- Settings: SingleThread/SettingsBindings.swift:36,50,68; UI in SingleThread/InterfaceSettingsView.swift (Show swipe prompt 134-142).
- Wire key: SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift:23 (case enableActionButtons, fallback true).
- Sync service: SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift push :256-257, payload key :387, receive :532-535.
- UI-test wiring: SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift:100.

## 4. Confirmation dialog / action menu presentation
- iOS: SingleThread/ContentView+ActionMenu.swift:25-63 - bottom-bar skipButton; when showActionMenu, sets isShowingActionMenu=true then .confirmationDialog(SharedStrings.reminder): Skip / "Reschedule" (->isShowingRescheduleSheet) / Delete (destructive). IDs: rescheduleButton, deleteButton.
- Shared reschedule sheet: SingleThread/ContentView+ActionMenu.swift:219-236 actionMenuRescheduleSheet (NavigationStack + Cancel), uses RescheduleSheet.
- macOS cluster: SingleThread/ContentView+ActionMenu.swift actionButtons (74-89): toggle ON -> macCompleteButton + macActionMenu; OFF -> Complete + macSkipButton + macDeleteButton. macActionMenu (92-134) Menu: Skip / "Reschedule" / Delete; macSkipButton 137-151; macDeleteButton 153-170. IDs completeButton/skipButton/deleteButton.
- Watch: SingleThreadWatch/WatchReminderView.swift:206-223 actionMenuDialogButtons (Skip / "Reschedule" / Delete) via .confirmationDialog("Reminder",...) at :283; skipButton gate at :144-158.
- Nudge sheet (iOS): SingleThread/ContentView+iOS.swift:50-121 - nudgeDeleteButton (id nudgeDeleteButton).

## 5. Shared localized keys (LocalizedStringResource, table "Localizable")
- SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:30 skipAction="Skip"; :40 deleteAction="Delete"; :27 completeAction="Complete"; :52 skipReminderAccessibility; :58 deleteReminderAccessibility; :34 reminder="Reminder".
- NOTE: "Reschedule" is NOT a SharedStrings key - hardcoded Button("Reschedule") in iOS (ContentView+ActionMenu.swift:50), macOS (:108), watch (WatchReminderView.swift:214). No shared "More" label/key exists.
- Catalog: SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings ("Skip":1310, "Delete":373, "Skip Reminder":1351, "Delete reminder":414). App catalog SingleThread/Resources/Localizable.xcstrings ("Reschedule":2713, "Skip Current Task":1021).

## 6. Tests
- Unit - ActionMenuGate truth table: SingleThreadTests/ActionMenuGateTests.swift:4-15 (2x2x2 enableActionButtons x canMutate x hasVisibleReminder).
- Unit - swipe logic: SingleThreadTests/SwipeGestureDecisionTests.swift (threshold/direction/dominance). Reveal UI: SingleThreadTests/SwipeToActModifierTests.swift (Complete/Skip label, alignment).
- Unit - toggle/gating: SingleThreadTests/ActionButtonTests.swift, EnableActionButtonsSyncTests.swift, EnableActionButtonsMigrationTests.swift, SettingsViewTests.swift (:54,:120), BoolPreferenceKeyTests.swift:14, AppViewModelSyncWiringTests.swift:18.
- Watch unit: SingleThreadWatchTests/ShowEnableActionButtonsStateTests.swift (:64), WatchSyncPipelineTests.swift (:398-437), WatchReminderViewRegressionTests.swift, WatchReminderViewModelTests.swift.
- UI tests: SingleThreadUITests/SingleThreadUITests.swift - smoke (:33-58 asserts skipButton/completeButton w/ enableActionButtons ON), testOverThresholdSwipeCompletesReminder (:81-141, drag ~110pt past 72pt threshold), testLanguageSelectionChange... (:143+). No UI test for swipe-skip action menu or swipe-left reveal.
