# Q6 — Test seams, UI tests, and unit tests for toggles / skip / skip-nudge / delete

All file:line references verified by reading the cited regions. Repo root: /Users/vardy/dev/alanvardy-var-780-add-additional-actions.

## 1. iOS `--seed '<json>'` seam (UITestingSeed → InMemoryEventStore)

- SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift
  - JSON schema doc: :8-17 — reminders[] (title, notes?, priority?), calendars[], excludedLists[], completionCount (default 0), skipCounts (title-keyed, default {}), isEntitled (default false), hasHidden (default false), entitlementUnresolved (default false).
  - fromLaunchArguments(_:): :18-26 — finds --seed, requires index + 1 < arguments.count, decodes SeedPayload; nil when absent/malformed.
  - resetPersistedState(): :31-50 — removes every key in persistedKeys (:60-92) from BOTH AppGroup.defaults and UserDefaults.standard. persistedKeys includes skippedReminderIdentifiers, skipCounts, excludedListTitles, showDate, showList, showRecurrence, showAlarms, showCompletionGlow, showUndatedReminders, sortOption, completionCount, isEntitled, enableActionButtons (:86), showMicrophoneButton, showSwipePrompt, showUndoButton, backgroundEnabled, backgroundFadePercent, backgroundPinned, allowsLandscape, textSize, appearanceMode, notificationsEnabled, notificationIntervalHours.
  - SeedPayload decode :97-134 (decodeIfPresent ?? default); ReminderSeed title/notes?/priority? :114-117; pinned CodingKeys :166-172.
  - materialize(): :137-159 — real EKEventStore(), EKCalendars, EKReminders; reminder.priority set only when present; calendar = createdCalendars.first; title-keyed skipCounts resolved to identifier-keyed.
- SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift
  - Init :14-25 (reminders, calendars, deliverCompletionOffMain, defaultCalendar).
  - Seam guarantees: authorizationStatus → .fullAccess :40-42; requestFullAccessToReminders → true :47-49; fetchReminders returns allReminders.filter { !$0.isCompleted } :55-56; save appends :76-78; remove by calendarItemIdentifier :80-82; makeReminder :84-106 backed by process-wide sharedStore :118-121, calendar = defaultCalendar ?? calendars.first.
  - #if !os(watchOS) guards save/remove/makeReminder :74-109.
- Wiring (SingleThread/AppViewModel.swift):
  - init(arguments:) :21-91 → Self.makeStore :22; usesInMemoryStore :24; WatchConnectivity activation suppressed when usesInMemoryStore :29.
  - makeStore :273-276: seed present → seededStore(seed), usesInMemory = true.
  - seededStore(_:): :329-383:
    - UITestingSeed.resetPersistedState() :330
    - InMemoryEventStore(reminders: seed.reminders, calendars: seed.calendars, defaultCalendar: seed.calendars.first) :331-334
    - AppGroup.defaults.set(seed.completionCount, "completionCount") (unclamped) :344-346
    - AppGroup.defaults.set(seed.skipCountsByIdentifier, "skipCounts") :352-354
    - UserDefaults.standard.set(true, forKey: "enableActionButtons") :350 — the --seed path force-enables the action-buttons toggle (after reset wipes it).
    - Entitlement selection :351-355 (entitlementUnresolved > isEntitled > not-entitled).
    - ReminderStore(eventStore:loadsReminders: !emptyWithHidden, hasHidden:, completionCounter: CompletionCounterStore(defaults: AppGroup.defaults, key: "completionCount"), entitlementStore:) :357-364; emptyWithHidden :356.
    - store.setExcludedListTitles when non-empty :365-367.
  - Ordering: reset (wipes enableActionButtons) at :330, re-set at :350 → every seeded launch ends with toggle on.

## 2. iOS `--ui-testing` seam

SingleThread/AppViewModel.swift makeStore :277-311 (no --seed):
- --reset-glow-preference removes showCompletionGlow :287-290; --reset-swipe-preference removes showSwipePrompt :288-291.
- UserDefaults.standard.set(true, forKey: "enableActionButtons") :291 — iOS --ui-testing also force-enables the toggle.
- Deterministic single-reminder store: InMemoryEventStore(reminders: [], calendars: []) → makeReminder("Buy groceries", "Don't forget the milk"); reminder.priority = 5 :292-305; ReminderStore(eventStore:loadsReminders: false, reminders: [reminder], skippedIDs: [], authorizationStatus: .fullAccess, entitlementStore: EntitlementStore(testingWithEntitled: false)) :296-309; usesInMemory = false :311 (WatchConnectivity IS wired under iOS --ui-testing).
- Fallback: loads = !--ui-testing && !--no-reminders :314-316.

## 3. Watch `--ui-testing` seams

SingleThreadWatch/WatchAppViewModel.swift:
- init :13-65: --ui-testing → Self.uiTestingStore(arguments:) :17-22; production → ReminderStore(loadsReminders: true).
- Watch has NO enableActionButtons key anywhere (grep: only iOS files: ContentView.swift:96-97, SettingsBindings.swift:25,44,67, InterfaceSettingsView.swift:20,87, ContentViewModel.swift:57-60, AppViewModel.swift:291,350, UITestingSeed.swift:86, + tests). Watch buttons render unless canMutate false.
- Watch sub-seams: --ui-testing-gated :26-30 (AppGroup.defaults["completionCount"] = freemiumCap → canMutate false → upgrade prompt); --ui-testing-glow-disabled / --ui-testing-glow :43-56 (apply(false)/apply(true) + glow duration 2.0s).
- uiTestingStore(arguments:) :96-152:
  - Sample reminder "Buy groceries", priority = 5, notes "Don't forget the milk" :99-101.
  - --ui-testing-priority <n> :113-120 (parsed before excluded-list loop).
  - --ui-testing-skip-count <n> :123-131 (AppGroup.defaults["skipCounts"] = [calendarItemIdentifier: n]).
  - --ui-testing-excluded-list "<list>" / --ui-testing-live-excluded "<list>" :134-146 (calendar titled <list>; excludedListTitles set :144-146 / empty).
  - Default return :148-152: InMemoryEventStore(reminders: [reminder]) + ReminderStore(loadsReminders: false, reminders: [reminder], skippedIDs: [], authorizationStatus: .fullAccess).
- setupSyncService :157-217: onCompleteReminder relay :207-208; onDeleteReminder relay :209-210; scheduleUITestLiveExcludedDelivery :239-249 (real didReceiveApplicationContext 5 s after launch).

## 4. UI tests — skip, skip-nudge (reschedule/delete), delete

### iOS SingleThreadUITests/
Base SingleThreadUITestCase.swift: launchApp :16-21, launchSeeded :23-25 (["--seed", json] + extra), flipToggle(_:target:) :28-42, assertTogglePersists(toggleID:settingsRowID:expectedValue:message:) :45-60, statusLabel :62-75.

SingleThreadUITestsFlows.swift (--seed seam):
- testListShowsSeededReminder :29-39; testEmptyListShowsNoRemindersState :41-49; testNothingDueShowsWhenRemindersHidden :51-58.
- SKIP: testSkipAdvancesToNextReminder :60-79 (priorities 1 & 9; First shown; swipeLeft → buttons["Skip"]; tap → Second shown). testSkipAllShowsAllDoneState :81-97 (→ emptyStateTitle). testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder :99-143 (Complete swipeRight, Skip, then non-existence asserts).
- COMPLETE: testCompleteViaSwipeRemovesReminder :145-159.
- DELETE: testDeleteViaContextMenuRemovesReminder :161-176 (press 1.0s → deleteButton → emptyStateTitle).
- TOGGLES/persistence (--ui-testing relaunch, never --seed): testBackgroundAndPinTogglesPersistAcrossRelaunch :289-361 (bg default "1" :312, pin default "0" :317); testReminderTogglesPersistAcrossRelaunch :425-465 (showList default "0" :433, glow default "1" :438); testSwipePromptToggleRoundTripsViaSettings :552-594 (default "1" :565); testUndoButtonHiddenWhenToggleOff :632-663.
- Freemium: testUpgradePromptAppearsWhenGated (completionCount cap, isEntitled false → upgradeButton), testActionClusterAppearsWhenEntitledAtCap (→ completeButton), testUnresolvedEntitlementRendersNoUpgradeButton, testSettingsHasPurchaseRow, testPurchaseSheetHasRestoreButton.

ActionButtonsUITests.swift (--ui-testing):
- testActionButtonsRenderAndSkipAdvancesCard :21-41 (completeButton + skipButton present; tap Skip → emptyStateTitle).
- testActionButtonsAccessibilityAudit :43-63. Comment :15-17 documents the toggle-on seeding in SingleThreadApp.makeStore.

SkipNudgeUITests.swift (--seed + skipCounts):
- Shared seed :20-21: {"reminders":[{"title":"Buy groceries"}],"skipCounts":{"Buy groceries":5}}.
- testSkipNudgeBannerAppearsAfterSixthSkipAndDeletes :26-51 (skipNudgeBanner → nudgeSheetTitle → nudgeDeleteButton → emptyStateTitle).
- testSkipNudgeRescheduleActs :55-84 (nudgeRescheduleButton → dueDateText; banner gone).
- testSkipNudgeViewInRemindersOpensURL :88-137 (nudgeViewInRemindersButton + --url-opener-spy → lastOpenedURL spy label, x-apple-reminderkit://REMCDReminder/ + 36-char UUID).

NotificationsSettingsUITests.swift: testNotificationsToggleExists :15-29 (notificationsEnabledToggle defaults "0").
NotificationsUITests.swift: flipToggle(target: "1") :30, persisted "1" :91-99, statusLabel seam.
NotificationSchedulingUITests.swift:18-24 same flipToggle pattern.

### Watch SingleThreadWatchUITests/
SingleThreadWatchUITestsFlows.swift:
- testCardShowsReminderTitleAndNotes; testPriorityMarkerRendersForMidRangeValue :19-31 (["--ui-testing","--ui-testing-priority","7"] → priorityMarker).
- testExcludedListDoesNotRenderReminder :33-45; testLiveExclusionHidesReminderWithoutRelaunch :48-59.
- COMPLETE: testCompleteRemovesReminder :63-73.
- SKIP: testSkipShowsAllDoneState :77-88.
- SKIP-NUDGE: testSkipNudgeShowsDeleteDialog :92-120 (["--ui-testing","--ui-testing-skip-count","5"]; skip tap → banner → app.buttons["Delete"] matched BY LABEL → emptyStateTitle).
- DELETE: testDeleteViaConfirmationDialogRemovesReminder :124-138 (tap card → "Delete" label → empty state).
- testRefreshPresentOnNoRemindersState; testUpgradeOniPhoneShowsWhenGated :158-175 (--ui-testing-gated → upgradePrompt, completeButton absent); testCompleteHoldsCardDuringGlow :177-211 (--ui-testing-glow).

SingleThreadWatchUITests.swift: testTapRevealsConfirmationDialog (matches "Refresh" BY LABEL), testAccessibilityAudit.

## 5. Unit tests

### Preference structs (default-on vs default-off proof)
Pattern: UUID key in UserDefaults.standard, defer removeObject, assert missing-key default then set(false)/set(true) round-trip.
- SingleThreadTests/ShowDatePreferenceTests.swift:8-19 — missing key → #expect(preference.isEnabled) (default-ON) + isEnabled != false guard.
- ShowAlarmsPreferenceTests.swift:8-18 — default-ON.
- ShowRecurrencePreferenceTests.swift:8-18 — default-ON.
- ShowCompletionGlowPreferenceTests.swift:7-18 — default-ON ("missing key must never read as false").
- ShowListPreferenceTests.swift:8-19 — default-OFF (#expect(!preference.isEnabled, "absent key defaults to disabled")).

### ReminderStore operations (SingleThreadTests/ReminderStoreTests.swift)
- addReminderSucceedsAndKeepsExistingReminders :222-…
- skipCurrentReminderNoOpsAndNotifies :245-280; skipCurrentReminderRefetchesAndDropsCompletedReminder :282-311; skipCurrentReminderRefetchKeepsSkippedReminder :313-341; skipCurrentReminderDiscardedAfterClearSkipped :343-363.
- completeCurrentReminderCompletesVisibleAndNoOpsOtherwise :368-399; completeReminderDoesNothingWhenIdentifierNotFound :403-411.
- lifecycleGuardsRespectLoadsRemindersFlag :416-437; hasHiddenReflectsSeedsAndSets :440-465; allSkippedReflectsState :468-500.
- ReminderStoreSkipCountTests :505+ (serialized suite): incrementsSkipCountOnInteractiveSkip :515-…; nudgeInterruptsSixthSkipAndKeepsReminderVisible :559-579 (seed 5 → 6th fires onSkipNudgeRequested, count 6, skippedIDs empty, reminder visible); nudgeDoesNotFireAtFive :582-605; nudgeDoesNotRefireAfterThreshold :…631 (7th advances); completeResetsSkipCount :634-651; deleteResetsSkipCount :654-671; rescheduleResetsSkipCount :673-692 (#if !os(watchOS)).

### EventKit write path (SingleThreadTests/EventKitStoringTests.swift, FakeEventStore)
- completeReminderMarksSavedAndReloads :150-167; completeReminderSaveErrorStaysSilentAndSkipsReload :169-…
- deleteReminderRemovesAndReloads :240-…; deleteReminderRemoveErrorStaysSilentAndSkipsReload :258-…; deleteReminderWhileSkippedPrunesSkipIDOnReload :330-…
- reschedulePersistsDueDateAndReloads :273-293; rescheduleUnknownIdentifierIsNoop :297-310; rescheduleFailureReturnsFalse :312-327 (no reload on save error).

### Gating (SingleThreadTests/ReminderStoreGateTests.swift)
- canMutate 4-combination table :21-45; completeReminderReturnsFalseWhenGated :47-62; completeReminderIncrementsCounterOnSuccess :64-80; skipCurrentReminderNoOpsWhenGated :83-99; skipCurrentReminderWorksWhenNotGated :101-122; deleteReminderNoOpsWhenGated :130-…. noopSettle seam :9.

### Action-button gate (SingleThreadTests/ActionButtonTests.swift, #if os(iOS))
- buttonsShowWhenToggleOnAndReminderVisible :25-31; buttonsHiddenWhenToggleOff :35-41; buttonsHiddenWhenNoVisibleReminder :45-59; buttonsHiddenWhenAllSkipped :63-80. Each set + defer removeObject on UserDefaults.standard["enableActionButtons"]. Gate: SingleThread/ContentViewModel.swift:57-60.

### Seed parsing (SingleThreadTests/UITestingSeedTests.swift)
parsesRemindersFromCompactJSON :12-25 (priority:1 round-trip), parsesCalendarsAndExcludedLists :27-37, parsesCompletionCountAndIsEntitled :39-47, defaults :49-57, preservesOutOfDomainCompletionCountVerbatim :59-70 (250), parsesEntitlementUnresolved :72-80, hasHidden :91-107, returnsNilWhenSeedAbsentOrMalformed :109-115, inMemoryStoreRendersSeededRemindersThroughStore :117-132, resetPersistedStateClears* :134-….

### Skip logic (SingleThreadTests/ReminderSkipTests.swift)
ReminderSkipLogicTests resolve/skipping tables; ReminderPriorityTests levelMapsEveryPriority (0-9), displayNameLocalizes, markerAndRankMap; ReminderSortTests; ReminderNotesFormatterTests.

### SkipCountStore (SingleThreadTests/SkipCountStoreTests.swift)
shouldNudgeFiresOnlyAtOrPastThreshold :34-47 — table (0,false)…(5,false),(6,true),(7,true),(20,true); SkipCountLogic.shouldNudge + defaultThreshold = 6 (SingleThreadCore/Sources/SingleThreadCore/SkipCountStore.swift:7,13-16).

### Watch unit tests (SingleThreadWatchTests/)
Present: ReminderStoreWatchTests.swift, ShowCompletionGlowStateTests.swift, WatchAppViewModelTests.swift, WatchReminderViewRegressionTests.swift, WatchSyncPipelineTests.swift (not line-read this pass).

## 6. How a settings toggle default-on/off is verified in tests

1. UNIT (preference structs): never-written UUID key → missing-key read defines default: #expect(isEnabled) for default-on (ShowDatePreferenceTests.swift:13, ShowAlarmsPreferenceTests.swift:13, ShowRecurrencePreferenceTests.swift:13, ShowCompletionGlowPreferenceTests.swift:12); #expect(!isEnabled) for default-off (ShowListPreferenceTests.swift:12-15). ShowDate/ShowCompletionGlow also assert isEnabled != false.
2. UI (XCTest): persisted key first removed so the DEFAULT applies (via --seed resetPersistedState, or --reset-glow-preference/--reset-swipe-preference under --ui-testing), then rendered switch value asserted: default-on as "1" (backgroundToggle SingleThreadUITestsFlows.swift:312; showCompletionGlowToggle :438; "Show swipe prompt" :565), default-off as "0" (pinWallpaperToggle :317; showListToggle :433; notificationsEnabledToggle NotificationsSettingsUITests.swift:26). Persistence across relaunch: flipToggle (SingleThreadUITestCase.swift:28-42) → terminate → relaunch with --ui-testing (never --seed — comments :7-8 and :427-431) → re-assert flipped value; packaged as assertTogglePersists :45-60.

## 7. Cross-cutting observations (verified)

- Both iOS seams force the action-buttons toggle: --ui-testing (AppViewModel.swift:291) and --seed (seededStore :350, after reset wipes it at :330). Watch has no enableActionButtons; buttons gated only by canMutate (ReminderStore.swift:170-172), --ui-testing-gated stages the gated state.
- All mutations gate on canMutate: completeReminder ReminderStore.swift:215, deleteReminder :291, rescheduleReminder :349, skipCurrentReminder :371, skipCurrentReminderImmediately :412.
- 6th-skip nudge: skipCurrentReminder :370-398 fires onSkipNudgeRequested (:95, :377) and returns without advancing. Wired in ContentViewModel.swift:25-27 (iOS) and WatchReminderViewModel.swift:28-30 (watch).
- Nudge UI identifiers: skipNudgeBanner (ReminderCardView.swift:158; watch WatchReminderView.swift:230-234), nudgeSheetTitle (ContentView+iOS.swift:64), nudgeDeleteButton/nudgeRescheduleButton/nudgeViewInRemindersButton; watch dialog Delete matched by label.
- UI tests match "Skip"/"Complete" swipe actions by label, buttons by identifiers (completeButton, skipButton, deleteButton, skipNudgeBanner), watch dialog actions by label.
