# Research Findings — VAR-1123

Answers to `questions.md`. Every claim carries a `file:line` reference;
paths are relative to the repo root.

## Q1: How does the swipe gesture pipeline work end to end?

### Shared pure logic (`SingleThreadCore`)
- `SwipeGestureOutcome` = `.complete | .skip | .none` — `SingleThreadCore/Sources/SingleThreadCore/SwipeGesture.swift:4`.
- `SwipeGesture.releaseDistance = 72` is the fixed release threshold — `SwipeGesture.swift:15`.
- `outcome(for:threshold:)` (`SwipeGesture.swift:21-33`): vertical-dominant drag (`|dy| > |dx|`) returns `.none` so List scroll/pull-to-refresh win (`:24`); released `width >= threshold` → `.complete`, `width <= -threshold` → `.skip`, else `.none`.
- `revealedOutcome(forOffset:)` (`SwipeGesture.swift:34-40`) maps a *live* offset only: `>0` → `.complete`, `<0` → `.skip`, `0` → `.none`. It drives the reveal panel, not the final decision.

### iOS modifier + reveal panel (`SingleThread/SwipeToActModifier.swift`)
- `SwipeToActModifier.body` (`:88-123`) is a ZStack of an optional `SwipeRevealPanel` behind the content, offset by `dragOffset`.
- `DragGesture(minimumDistance:10)` attached `.simultaneousGesture` (`:101`); `.onChanged` writes `dragOffset = value.translation.width` (`:103-104`); `.onEnded` (`:105-110`) calls `SwipeGesture.outcome(...)`, animates the offset back to 0, and fires `onOutcome(outcome)` when the result is not `.none`.
- Panel visibility: `revealedOutcome` (`:134-135`) computed from `dragOffset`; panel shown only when it is not `.none` (`:91-92`). `progress` (`:128-131`) = `min(|dragOffset| / max(threshold,1), 1)` drives opacity.
- `SwipeRevealPanel.alignment(for:)` (`:34-36`): `.skip` → `.trailing`, otherwise `.leading`.
- `SwipeRevealPanel.presentation` (`:43-72`): `.complete` → `SharedStrings.completeAction` + `"checkmark.circle.fill"` + `CardPlate.completeHintColor` (`:55-59`); `.skip` → `SharedStrings.skipAction` + `"circle.slash"` + `CardPlate.skipHintColor` (`:60-64`). Body renders a `Label`, `.headline`, tint, `.cardPlate`, full-frame alignment, `.opacity(progress)` (`:16-27`).
- Accessibility on the modifier: `contentShape(Rectangle())` (`:98`), `accessibilityAction(completeAction)` → `onOutcome(.complete)` (`:114`) and `accessibilityAction(skipAction)` → `onOutcome(.skip)` (`:117`); the layer carries `accessibilityIdentifier(reminderCard)` (`:120`).

### Dispatch
- Attached at `SingleThread/ContentView.swift:459-467` on `ReminderCardView`: `.complete` → `Task { await viewModel.completeCurrentReminder() }`; `.skip` → `viewModel.skipCurrentReminder()`; `.none` → break.
- `ContentViewModel.completeCurrentReminder()` (`SingleThread/ContentViewModel.swift:185-194`); `skipCurrentReminder()` (`:196-198`) forwards to `store`.

### Other platform consumers
- Only the iOS `ContentView` consumes `SwipeGesture`/`SwipeToActModifier`. macOS exposes Complete/Skip as menu/command buttons calling the store directly — `SingleThread/MenuBarExtraOptions.swift:25-30`, `SingleThread/SingleThreadApp+Commands.swift:33-42` — never via `SwipeGestureOutcome`. Watch, widget, and core have no `swipeToAct` consumer. Other platforms reuse the underlying store mutations but not the swipe decision types.

## Q2: How is the Skip / Schedule / Delete action menu constructed per platform?

### Shared gate
- `ActionMenuGate.showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:)` = logical AND of the three — `SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:7,12`. Used by iOS and macOS.

### iOS — `confirmationDialog`
- State: `isShowingActionMenu` (`SingleThread/ContentView.swift:126`); `actionMenuReminder: EKReminder?` captured on tap (`:133`).
- `showActionMenu` calls the shared enum — `SingleThread/ContentView+ActionMenu.swift:19`.
- `skipButton` (`ContentView+ActionMenu.swift:29`): when `showActionMenu`, sets `actionMenuReminder = visibleReminders.first` + `isShowingActionMenu = true`; otherwise calls `skipCurrentReminder()` directly (`:25-36`). a11y id `skipButton`.
- `.confirmationDialog(SharedStrings.reminder, isPresented: $isShowingActionMenu)` (`:46`); buttons (`:47-59`) in order: `Button(SharedStrings.skipAction)` (no role), `Button("Reschedule")` → reschedule sheet (id `rescheduleButton`), `Button(SharedStrings.deleteAction, role: .destructive)` (id `deleteButton`).
- Bottom bar `actionCluster` = complete / mic / skip (`ContentView.swift:539`), rendered when `showsActionButtons` (`:743`).

### macOS — action cluster
- `macShowActionMenu` uses the same enum — `ContentView+ActionMenu.swift:84`.
- `actionButtons` HStack(spacing:32) (`:76`): toggle ON → `macCompleteButton` + `macActionMenu`; OFF → `macCompleteButton` + `macSkipButton` + `macDeleteButton`. Rendered from `bottomBar` when `showsActionButtons` (`ContentView.swift:697-700`).
- `macActionMenu` is a SwiftUI `Menu` (`:101`, `.menuStyle(.borderlessButton)`, `.keyboardShortcut("s")`, label id `skipButton`) with items (`:102-111`): Skip, `Button("Reschedule")`, Delete (`.destructive`, `.keyboardShortcut(.delete)`).
- `macSkipButton:119` (`skipButton`), `macDeleteButton:137` (`deleteButton`), `macCompleteButton:93` (`completeButton`, `.keyboardShortcut("c")`).

### Shared reschedule sheet (iOS + macOS)
- `actionMenuRescheduleSheet` (`ContentView+ActionMenu.swift:179`) wraps `RescheduleSheet` in a NavigationStack with a Cancel toolbar item; reminder from `actionMenuRescheduleReminder` (iOS captured-or-visible `:65`; macOS visible `:171`). Attached via `ContentView.swift:327` `.sheet`.
- `RescheduleSheet` (`SingleThread/RescheduleSheet.swift:3`): "Reschedule to" + DatePicker (date-only vs date+time via `hasDueTime`, `:67`), confirm `Label("Reschedule", systemImage:"calendar.badge.plus")` (`:48`, id `rescheduleConfirmButton`).

### watchOS — `confirmationDialog`
- `reminderCard` (`SingleThreadWatch/WatchReminderView.swift:277`) attaches `.confirmationDialog("Reminder", isPresented: $viewModel.isShowingActionMenu) { actionMenuDialogButtons }` (`:280` also `.sheet`).
- `actionButtons` (`:132`) = complete + skip; skip tap (`:143-144`): when `canShowActionMenu` → `isShowingActionMenu = true`, else skip directly.
- `actionMenuDialogButtons` (`:211-221`): Skip → `skipCurrentReminder()`; `Button("Reschedule")` → `isShowingRescheduleSheet = true`; Delete (`.destructive`) → `deleteCurrentReminder()`. No `accessibilityIdentifier` on any dialog button.
- Watch uses its **own** inline reschedule sheet (`WatchReminderView.swift:299`, id `rescheduleConfirmButton`), not the shared `RescheduleSheet`.
- State: watch `WatchReminderViewModel.swift:68` (`isShowingActionMenu`), `:71` (`isShowingRescheduleSheet`).

### Strings
- Shared action titles come from `SharedStrings` (`skipAction`, `deleteAction`, `completeAction`, `reminder`, `skipReminderAccessibility`). The word **"Reschedule" is a hardcoded literal on all three platforms** (`ContentView+ActionMenu.swift:50,117`, `WatchReminderView.swift:214`).

## Q3: How do `ActionMenuGate`, `enableActionButtons`, and `showsActionButtons` interact?

### Shared gate
- `ActionMenuGate.showsActionMenu` returns `enableActionButtons && canMutate && hasVisibleReminder` — `ActionMenuGate.swift:7,12`.

### Stored preference `enableActionButtons`
- iOS+macOS source of truth: `@AppStorage("enableActionButtons", store: AppGroup.defaults) var enableActionButtons = true` — `SingleThread/ContentView.swift:100`.
- View → VM: `.task { viewModel.enableActionButtons = enableActionButtons }` (`ContentView.swift:284`) and `.onChange` (`:292-293`).
- VM mirror: `SingleThread/ContentViewModel.swift:74-77` (defaults `true`).
- Migration: `SingleThread/AppViewModel.swift:141-145` copies `UserDefaults.standard["enableActionButtons"]` into `AppGroup.defaults`; resets to ON at `:273,367`.
- Settings: `SingleThread/SettingsBindings.swift:36,50,68`; toggle UI `SingleThread/InterfaceSettingsView.swift:106`; passed in `SettingsView.swift:49,59`.
- Key registry: `SingleThreadCore/Sources/SingleThreadCore/BoolPreferenceKey.swift:23` (`enableActionButtons`, fallback `true`).

### `showsActionButtons` render gate (iOS/macOS)
- `ContentViewModel.swift:96-97` = `enableActionButtons && hasLoadedReminders && store.visibleReminders.first != nil`; `hasLoadedReminders` (`:88-91`) flips true in `.task` after `ReminderStore.start()`.
- iOS render `ContentView.swift:743`; macOS render `ContentView.swift:698`.

### Shared-enum consumers vs watch inline gate
- iOS: `ContentView+ActionMenu.swift:18-24` calls the enum with the view-local `enableActionButtons`. macOS: `:85-91` calls the enum.
- Watch does **not** call `ActionMenuGate`: `WatchReminderView.swift:80-84` `canShowActionMenu = viewModel.showEnableActionButtonsState.isEnabled && store.canMutate && store.visibleReminders.first != nil` — same three conditions, but inlined.
- Watch enable holder: `SingleThreadWatch/ShowEnableActionButtonsState.swift:13,18` (reads `BoolPreferenceStore`, fallback `true`); `apply` persists to `AppGroup.defaults` (`:27`).
- Watch wiring: `WatchAppViewModel.swift:282-284` → `onEnableActionButtonsReceived`; sync receive in `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift:534-537` (push `:256-257`, payload key `:387`).

## Q4: How are action strings declared, consumed, and stored?

### Declaration
- `SharedStrings` is a `public enum` of typed `LocalizedStringResource` accessors — `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:11`.
- `completeAction` `:16`, `reminder` `:24`, `skipAction` `:31`, `deleteAction` `:38`, `skipNudgeTitle` `:41`; a11y labels `:44-52`; title-case macOS variants `completeReminder`/`skipReminder` `:26/:36` (both `// periphery:ignore`); interpolated `openLink(to:)` `:82` and `priorityAccessibilityLabel(_:)` `:90`.
- Doc comment `:5-6`: "Keys shared across ≥2 targets live here — never duplicated in a target's own catalog." `:12-13` records why "Medium" intentionally stays duplicated.
- `Reschedule` is **not** a `SharedStrings` member — it is a literal resolving against `.main`.

### Storage — String Catalogs
- Four catalogs: Core `SingleThreadCore/.../Resources/Localizable.xcstrings` (backs `.module`), App `SingleThread/Resources/Localizable.xcstrings`, Watch `SingleThreadWatch/Resources/Localizable.xcstrings`, Widget `SingleThreadWidget/Resources/Localizable.xcstrings`.
- Shape: `sourceLanguage: "en"`, `strings` → key → `extractionState` + per-locale `localizations` with `stringUnit.state`/`value`. App `"Reschedule"` at `SingleThread/Resources/Localizable.xcstrings:2713` (`extractionState: "manual"`), `"Reschedule to"` `:2754`.
- Watch catalog exists but no shared-key fixture observed in scope.

### Consumption
- Views: `Text(SharedStrings.x)` / `Label(...)` — swipe `SwipeToActModifier.swift:57,62,67,114,117`; iOS menu `ContentView+ActionMenu.swift:39,47,100,114,125,148,157`; macOS `SingleThreadApp+Commands.swift:32-40`, `MenuBarExtraOptions.swift:25,29` (via `resolvedInAppLanguage()`); watch `WatchReminderView.swift:134,149,212,219,258`; widget `NextThingWidget.swift:142,151`.
- Non-view resolution helpers: `LocalizedString+Shared.swift:118-133` (`resolved(in:)`, `resolvedInAppLanguage()` reading `AppLocaleState.storedEffectiveLocale`).

### Conventions
- Shared (≥2 targets): typed `SharedStrings` accessor + Core catalog entry; never duplicate into a target catalog.
- Target-only strings (`Reschedule`, `Reschedule to`, `Cancel`) stay literals against that target's catalog.
- Rename = accessor + catalog key in lockstep; any leftover unused accessor gets `// periphery:ignore`.
- Test fixtures a new shared key must join: `SingleThreadTests/AppLanguageTests.swift:77-82` (`sharedStringResolvesToEveryShippedLanguage`, all 6 languages), `:50-53` (`localizedStringResourceResolvesInExplicitLocale`), `SingleThreadTests/SingleThreadTests.swift:163-170` (`rescheduleStringResolvesInGerman`), `:147-151` (`rescheduleSheetTextButtonsKeepNativeChrome`), `SingleThreadTests/RescheduleSheetTests.swift:52-79`.

## Q5: What test coverage exists for these paths?

### Unit — swipe decision logic `SingleThreadTests/SwipeGestureDecisionTests.swift`
- `:10` rightPastThresholdCompletes, `:14` leftPastThresholdSkips, `:18` underThresholdDoesNothing, `:23` verticalDominantDragDoesNothing, `:28` horizontalEqualToVerticalIsNotVerticalDominant, `:33` exactlyAtThresholdFires, `:40` customThresholdOverrideIsHonoured, `:46/:51/:56` reveal-label mapping.

### Unit — reveal panel `SingleThreadTests/SwipeToActModifierTests.swift`
- `:11` completePanelShowsCompleteLabel, `:17` skipPanelShowsSkipLabel, `:26/:31` anchors (complete → leading / skip → trailing), `:40` idleModifierWrapsContentWithoutPanel.

### Unit — swipe prompt `SingleThreadTests/SwipePromptTests.swift`
- `:9` promptShownWhenEnabled, `:30` promptHiddenWhenDisabled, `:37` dismissButtonHasAccessibilityLabel.

### Unit — action-menu gating
- `SingleThreadTests/ActionMenuGateTests.swift:10` full 2×2×2 truth table.
- `SingleThreadTests/ActionButtonTests.swift:21,30,42,47,55,62` — `showsActionButtons` gate + cold-open ordering.

### Unit — enable toggle migration/sync
- `SingleThreadTests/EnableActionButtonsMigrationTests.swift:13,20,29` (serialized, real `UserDefaults`).
- `SingleThreadTests/EnableActionButtonsSyncTests.swift:20,28,38,49` (serialized, watchOS/iOS).
- `SingleThreadWatchTests/ShowEnableActionButtonsStateTests.swift:10,16,22,28,37`; `SingleThreadWatchTests/WatchSyncPipelineTests.swift:398-437`.
- Also `SingleThreadTests/AppViewModelSyncWiringTests.swift`, `SingleThreadTests/BoolPreferenceKeyTests.swift:14`, `SingleThreadTests/SettingsViewTests.swift:54,120`.

### Unit — reschedule sheet
- `SingleThreadTests/RescheduleSheetTests.swift:12-79` (date-only vs time, write-back mask, label placement, prominent confirm).

### UI tests `SingleThreadUITests/SingleThreadUITests.swift`
- `:23` smoke — asserts `completeButton`/`skipButton`/`dictateButton` render, then a11y audit (`.sufficientElementDescription`, `.trait`).
- `:73` `testOverThresholdSwipeCompletesReminder` — `--seed` + `--ui-testing-noop-settle`, 110pt right drag past the 72pt threshold, asserts the seeded reminder disappears.
- Language tests `:140`/`:187` unrelated.
- Watch UI `SingleThreadWatchUITests/SingleThreadWatchUITests.swift:11` is a render smoke only.

### Gaps (what does NOT exist)
- No UI test drives the Skip button/skip flow, the action-menu `confirmationDialog`, or the reschedule sheet.
- No watch UI test drives swipe/buttons; no iOS UI test asserts reveal-panel labels at the UI layer.

## Q6: What accessibility seams exist on the swipe and action surfaces?

### Swipe surface
- `SwipeToActModifier.swift:98` `contentShape(Rectangle())`; `:114`/`:117` `accessibilityAction` for complete/skip; `:120` `accessibilityIdentifier(reminderCard)`. Hit region = `contentShape` only; no explicit min-height padding.
- UI test drags `app.descendants(.any)[reminderCard]` ~110pt (`SingleThreadUITests.swift:95-115`).

### Action surface
- iOS corner plates: delete (label + id `deleteButton`, **no** `.isButton`) `ContentView.swift:493-494`; complete (label + id + `.isButton`) `:534-536`. `ContentView+ActionMenu` duplicates: complete `:107-109`, skip (`.isButton`) `:132-150`, delete (no trait) `:163-165`.
- Plate hit-region padding clearing 56pt plates: `ContentView.swift:196-197,224-225,242-243`.

### Card & nudge
- `ReminderCardView`: `children.combine` `:157`, per-link `accessibilityActions` `:159-168`, `contentShape` + label + `skipNudgeBanner` id `:190-195`, `swipePromptDismissButton` `:241-242`; child ids `priorityMarker`/`dueDateText`/`recurrenceLabel`/`listNameText`/`alarmLabel`/`notesText` `:107-151`.
- `ReminderDisplayRow` `accessibilityActions` `:29` + `filteredRemindersRow` id `:38`.

### watchOS
- `WatchReminderView`: complete/skip/refresh label + id + `.isButton` `:138-155,248,206`; `reminderCard` id `:252`; nudge ids `:261,266`; reschedule ids `:301,307`. Glow seam `accessibilityHidden(!isGlowUITesting)` + `children.ignore` + `completionGlowOverlay` id `:194-197`.

### Audit exercise
- `SingleThreadUITests.swift:45-51` asserts `completeButton`/`skipButton`/`dictateButton` exist, then `:59` `performAccessibilityAudit(for: [.sufficientElementDescription, .trait])`; `.dynamicType`/`.hitRegion` deliberately excluded (`:53-58`, can hang on CI; covered by unit suites). macOS branch uses default audit (`:67`). Runs on every smoke launch.
- Key shared IDs: `deleteButton`, `completeButton`, `skipButton`, `dictateButton`, `settingsButton`, `refreshButton`, `undoButton`, `upgradeButton`, `reminderCard`, `skipNudgeBanner`, `swipePromptDismissButton`, `completionGlowOverlay`.

## Cross-Cutting Observations
- **Two action surfaces per platform, one shared gate.** iOS/macOS call `ActionMenuGate` (`ActionMenuGate.swift:7`); the watch reimplements the same AND inline (`WatchReminderView.swift:80-84`). The `enableActionButtons` axis is supplied by `@AppStorage`/`AppGroup.defaults` on iOS/macOS and by `ShowEnableActionButtonsState` on watch.
- **The "Skip" label appears in three distinct roles**: the swipe-reveal panel label (`SwipeToActModifier.swift:60-64`), the `accessibilityAction` name (`:117`), and the action-menu/button title (`SharedStrings.skipAction`). All resolve through the single Core catalog key `"Skip"`.
- The iOS swipe path is the **only** consumer of `SwipeGesture`/`SwipeToActModifier`; macOS/watch express Complete/Skip/Delete through buttons, `Menu`, or `confirmationDialog` instead.
- `confirmationDialog` is the established menu mechanism on iOS (`ContentView+ActionMenu.swift:46`) and watch (`WatchReminderView.swift:277`); macOS uses a native `Menu` (`:101`).
- Reschedule is the sole action without a shared string: hardcoded literal on all three platforms, cataloged only in the App catalog.
- The `enableActionButtons` preference is multi-layer: `@AppStorage` → VM mirror → computed `showsActionButtons`, with migration from `.standard` and a WatchConnectivity sync path.

## Open Areas
- Whether the App catalog contains its own `Complete`/`Skip`/`Delete` duplicates alongside Core's keys was not fully enumerated (Core catalog authoritatively backs the shared accessors).
- No watch-catalog localization fixture was observed for the shared action keys.
- The watch's inline gate vs the shared enum is behaviorally equivalent today, but no test asserts they stay in lockstep (no cross-target test coupling `canShowActionMenu` to `ActionMenuGate`).
- No UI-level assertion exists for reveal-panel labels or for the action-menu/skip flows; only unit/reflection coverage.