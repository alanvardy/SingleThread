# Q3 - Skip action surfaces: inventory, gating, accessibility, idiom styling

Every claim below was verified by reading the cited region.

## 1. Shared building blocks (used by every surface)

- Label/title strings: `SharedStrings.skipAction` = "Skip" (`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:16-18`); `skipReminderAccessibility` = "Skip reminder" (`:33-35`); `skipNudgeTitle` = "Skipped 6 times" (`:24-27`).
- Symbol + tint idiom shared everywhere: `systemImage: "circle.slash"` with `.tint(.orange)` (iOS cluster `SingleThread/ContentView.swift:347,351`; macOS `:347,351`; watch `SingleThreadWatch/WatchReminderView.swift:133,136`; widget `SingleThreadWidget/NextThingWidget.swift:153,156`; iOS trailing swipe `ContentView.swift:484,486`).
- Accessibility identifier `"skipButton"` on the four discrete buttons (cluster `ContentView.swift:535`, macOS `:354`, watch `WatchReminderView.swift:138`, widget `NextThingWidget.swift:159`); the trailing-swipe action has **no** identifier (found by XCUITest as `app.buttons["Skip"]` - `SingleThreadUITests/SkipNudgeUITests.swift:33-35`).
- Mutation gate shared by all paths at the store layer: `ReminderStore.canMutate` = `entitlementStore.isEntitled || completionCounter.count < EntitlementStore.freemiumCap` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:167-172`; cap = 100, `EntitlementStore.swift:57`). `hasResolvedEntitlement` mirrors `entitlementStore.hasResolvedEntitlement` (`ReminderStore.swift:174-179`).

## 2. iOS bottom-bar cluster (Complete / Mic / Skip)

- Cluster: `actionCluster` = `HStack(alignment: .center, spacing: 16) { completeButton; micButton; skipButton }` (`ContentView.swift:538-544`).
- iOS `skipButton`: `Button { viewModel.skipCurrentReminder() } label: { Label(SharedStrings.skipAction, systemImage: "circle.slash").labelStyle(.iconOnly).controlPlate() }` + `.accessibilityLabel(skipReminderAccessibility)` + id `skipButton` (`ContentView.swift:526-536`); `.controlPlate()` = fixed 56x56 circular plate (`SingleThread/ControlPlateModifier.swift:31-40,64-73`).
- **Gating chain** (`ContentView.swift:680-690`), only reached when `viewModel.dictation.canDictate && showMicrophoneButton` (line 680; if dictation is unavailable **or** the mic is hidden, the cluster never renders - the swipe remains):
  1. `!viewModel.store.hasResolvedEntitlement` -> `EmptyView()` (682-683)
  2. `!viewModel.store.canMutate` -> `upgradePrompt` (684-685)
  3. `viewModel.showsActionButtons` -> `actionCluster` (686-687)
  4. else -> `micButton` only (688-689)
- `showsActionButtons` (iOS-only): `UserDefaults.standard.bool(forKey: "enableActionButtons") && store.visibleReminders.first != nil` (`SingleThread/ContentViewModel.swift:52-61`).
- Preference `@AppStorage("enableActionButtons") var enableActionButtons = false` - **off by default** (`ContentView.swift:95-98`); Settings toggle "Show action buttons" / caption "Show complete, skip, and delete buttons.", id `showActionButtonsToggle` (`SingleThread/InterfaceSettingsView.swift:87-97`).

## 3. iOS trailing swipe

- `.swipeActions(edge: .trailing)` skip button, no identifier, `.tint(.orange)`: `ContentView.swift:480-487` (`viewModel.skipCurrentReminder()` at 482). Leading edge = Complete (`ContentView.swift:472-479`).
- **Gating**: none at the view level - the row is inside `if let reminder = viewModel.store.visibleReminders.first` (`ContentView.swift:428`); no `canMutate`/entitlement check wraps the swipe actions. Enforcement is the store guard in `skipCurrentReminder()` (`ReminderStore.swift:370-371`).
- iOS context menu contains **no skip** - only "View in Reminders" and Delete (`ContentView.swift:452-470`).
- Swipe prompt (visual hint "Swipe left to skip | Swipe right to complete"): `ReminderCardView.swift:163-220`; rendered when `showSwipePrompt` binding is true (`ReminderCardView.swift:37-41`); visual-only `.accessibilityHidden(true)` with reachable Dismiss id `swipePromptDismissButton` (`:183-204`); pref default true (iOS-only, `ContentView.swift:100-102`); non-iOS platforms get `.constant(false)` (`ContentView.swift:318-326`).

## 4. macOS action bar

- `#if os(macOS)` `actionButtons` (`ContentView.swift:328-377`): `HStack(spacing: 32)` of Complete / Skip / Delete, `.labelStyle(.iconOnly)`, `.font(.title)`. Skip button at 344-355: `viewModel.skipCurrentReminder()`, `.tint(.orange)` (351), `.keyboardShortcut("s", modifiers: [])` (352), a11y label `skipReminderAccessibility`, id `skipButton`. Complete has `.keyboardShortcut("c", modifiers: [])` (339).
- **Gating**: `bottomBar` renders the bar only when `viewModel.store.visibleReminders.first != nil` (`ContentView.swift:655-660`). No `canMutate` check at the view layer - the store guard no-ops (`ReminderStore.swift:370-371`).
- **No skip-nudge on macOS**: the 6th-skip interrupt is compiled only for `#if os(iOS) || os(watchOS)`; macOS takes the `#else` branch which increments the count without interrupting (`ReminderStore.swift:374-382`). `isNudged` is therefore always false on macOS (`ContentView.swift:437-440`).

## 5. Watch button

- Watch `actionButtons`: `HStack` of Complete / Skip (`WatchReminderView.swift:124-141`); skip `Button { viewModel.store.skipCurrentReminder() }` with `Label(circle.slash)`, `.tint(.orange)`, a11y label `skipReminderAccessibility`, id `skipButton`, `.accessibilityAddTraits(.isButton)` (`:130-139`).
- **Gating** (`WatchReminderView.swift:246-250`): `if !viewModel.store.canMutate, !viewModel.entitlementState.isEnabled { upgradeOniPhonePrompt } else { actionButtons }`. `upgradeOniPhonePrompt` ("Upgrade on your iPhone", id `upgradePrompt`) is shown when the phone free-tier cap is exhausted and the entitlement flag has not synced - no StoreKit surface on the watch (`:143-159`, comment at `:143-145`). Store-level `guard canMutate` also in `skipCurrentReminder()` (`ReminderStore.swift:371`).
- Watch has no swipe surface; delete is reached via the card tap-hold confirmation dialog (`WatchReminderView.swift:225-235`) and via the nudge dialog (below).

## 6. Widget intent

- `SkipReminderIntent` (`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:30-51`): `AppIntent`, `isDiscoverable = false` (41); `perform()` builds `ReminderStore(loadsReminders: true)`, applies sort, `reload()`, then `store.skipCurrentReminderImmediately()` (49).
- Widget button (`NextThingWidget.swift:152-159`): `Button(intent: SkipReminderIntent()) { Label(circle.slash).labelStyle(.iconOnly) }`, `.tint(.orange)`, `.buttonStyle(.bordered)`, a11y label, id `skipButton`. Rendered only in the `.reminder` state - `reminderView(display)` places `actionButtons` after `Spacer(minLength: 0)` (`NextThingWidget.swift:219-225`); `.noAccess/.empty/.allDone` states show message views instead (`:117-139`). Families: systemSmall/Medium/Large (`:115`).
- **Gating**: no widget-UI gate; `skipCurrentReminderImmediately()` enforces `guard canMutate` (`ReminderStore.swift:404-413`). It is the synchronous widget variant - no settle sleep because WidgetKit may suspend the process after `perform()` returns (comment `:406-409`).
- **Widget has no nudge UI**: on threshold cross the widget path still fires `onSkipNudgeRequested` but "Widget has no nudge UI; the count still persists so the paired phone/watch surfaces the prompt. The skip still applies." (`ReminderStore.swift:415-419`).

## 7. Skip-nudge banner (6th-skip interrupt)

- Threshold: `SkipCountLogic.defaultThreshold = 6` (`SingleThreadCore/Sources/SingleThreadCore/SkipCountStore.swift:12`); `crossedThreshold(from:to:)` fires **once** on first crossing (`:17-19`); counts persisted per-identifier under key `"skipCounts"` in App Group defaults (`:23-28`).
- Interrupt mechanics: `skipCurrentReminder()` -> `incrementSkipCount` (`ReminderStore.swift:561-568`) returns true on crossing -> `onSkipNudgeRequested?(identifier); return` - the card stays, skip does **not** advance (`ReminderStore.swift:370-379`). Hook declaration `ReminderStore.swift:92-95`; wired in `ContentViewModel.init` (`ContentViewModel.swift:25-27`, `nudgeIdentifier` at `:44-47`, `isNudged` at `:185-188`, `dismissNudge` at `:191-193`, `deleteNudgedReminder` `:196-200`, `rescheduleNudgedReminder` `:204-212`) and on watch (`WatchReminderViewModel.swift:28-30,49-55,79-81`).
- **iOS banner**: `ReminderCardView.nudgeBanner` (`ReminderCardView.swift:143-159`) - `exclamationmark.bubble` + `skipNudgeTitle`, `.buttonStyle(.borderedProminent)`, `.tint(.white)`, `.accessibilityLabel("Skipped 6 times - tap to manage")`, id `skipNudgeBanner`. Shown when `showNudge` (`ReminderCardView.swift:37-38`); fed by `showNudge: viewModel.isNudged(reminder.calendarItemIdentifier)` and `onNudgeTap: openNudgeSheet` (`ContentView.swift:429,441-442`). NOT accessibility-hidden (comment `:137-138`).
- **iOS nudge sheet** (iOS-only): `ContentView+iOS.swift:59-84` - "This reminder keeps coming back." (id `nudgeSheetTitle`), DatePicker (time offered only when the nudged reminder has a due time, `:91-100`), `nudgeRescheduleButton` (`:104-118`), `nudgeViewInRemindersButton` (`:129-140`), `nudgeDeleteButton` (`:145-153`), Cancel toolbar item (`:81-82`). Presented via `.sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() })` (`ContentView.swift:275-278`).
- **Watch banner**: `WatchReminderView.swift:230-244` - `if viewModel.isNudged(...)` -> Button id `skipNudgeBanner` -> `.confirmationDialog(skipNudgeTitle)` with Delete id `nudgeDeleteButton` (`:238-243`).
- **Not present on macOS or widget** (Sections 4, 6).
- UI-test coverage: iOS `SingleThreadUITests/SkipNudgeUITests.swift` (banner->sheet->Delete `:29-58`; Reschedule `:63-79`; banner-absent assertions `:88`; seeded via `--seed ... "skipCounts":{"Buy groceries":5}` so one tap crosses 5->6, `:21-25`); watch `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift:105-126` (seeds count 5, `skipButton` then `skipNudgeBanner`).

## 8. Platforms with no skip surface at all

- **None**: every platform has a skip affordance - iOS (bottom-bar cluster + trailing swipe), macOS (action bar), watchOS (button), widget (intent button). Gaps are partial:
  - No skip-nudge banner on macOS or widget.
  - No swipe anywhere except iOS (watch has buttons only; widget intent buttons only; macOS buttons only).
  - No skip in the iOS context menu (Delete + View-in-Reminders only, `ContentView.swift:452-470`).
  - The iOS bottom-bar cluster is invisible when dictation is unavailable, mic is hidden, entitlement is unresolved (EmptyView), gated (upgradePrompt), or the `enableActionButtons` toggle is off (mic-only) - swipe is then the only in-app iOS skip surface besides the widget/watch.

## 9. iPad vs iPhone styling of the same affordances

- **No idiom/size-class branching exists**: `rg` for `UserInterfaceIdiom|horizontalSizeClass|verticalSizeClass|idiom` across all Swift sources (SingleThread, SingleThreadCore, SingleThreadWatch, SingleThreadWidget, all test targets) returns zero matches. The cluster, swipe actions, and card render identically on iPad and iPhone.
- The only iPadOS-conditional styling is List chrome so the background photo shows through iPadOS opaque `List` backgrounds: `.scrollContentBackground(.hidden)` then `.background(Color.clear)` with an explanatory comment (`ContentView.swift:489-497`).
- Card row layout is device-agnostic: `.padding(.horizontal, 40)` + `.frame(maxWidth: .infinity, alignment: .center)` (`ContentView.swift:444-449`).
- `EmptyStateCard.maxContentWidth` = `min(340, viewportWidth * 0.6)` - "Relative so the card stays proportionate on iPads" (`EmptyStateCard.swift:37-44`).
- `controlPlate` is a fixed 56x56 plate on all iOS devices (`ControlPlateModifier.swift:34-40`).
- Both form factors are exercised by the same tests: CI runs iPhone 17 and iPad (A16) for unit, flows, and audit suites (`.github/workflows/ci.yml:25,93,154,213`); `ActionButtonsUITests` asserts the cluster `skipButton` on both (`SingleThreadUITests/ActionButtonsUITests.swift:20-58`).
- Cross-platform consistency: all five skip affordances share the `circle.slash` symbol, `.orange` tint, `SharedStrings.skipAction`/`skipReminderAccessibility` text, and the `skipButton` accessibility identifier (Sections 1-6).
