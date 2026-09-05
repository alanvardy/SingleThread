# Q2 — How iOS/macOS preference changes reach the watch

Verified by reading the cited lines. All paths relative to repo root /Users/vardy/dev/alanvardy-var-780-add-additional-actions.

## 1. Push side (iOS-only composition root, SingleThread/AppViewModel.swift)

The WatchConnectivity service is created and armed inside the #if os(iOS) block of AppViewModel.init (AppViewModel.swift:28-76):

- AppViewModel.swift:4-8 — #if os(iOS) imports (EventKit, UserNotifications, WatchConnectivity).
- AppViewModel.swift:30-44 — SkippedReminderSyncService(...) built with session: WCSession.default, skipStore: SkippedReminderStore(), showDateStore/showRecurrenceStore/showAlarmsStore/showCompletionGlowStore (each defaulting to AppGroup.defaults), entitlementStore: store.entitlementStore, and sendsShowDate: true, sendsEntitled: true (:39-40). Other sends*Service flags default to true inside the service init itself.
- AppViewModel.swift:46-55 — receive-side handlers assigned before activate(): onCompleteReminderReceived (Task toward store?.completeReminder), onDeleteReminderReceived, onExcludedListTitlesReceived, onSkipCountsReceived (→ store?.reload()).
- AppViewModel.swift:56 — service.activate().
- AppViewModel.swift:59 — syncService = service (property declared at :200-202, iOS-only).
- AppViewModel.swift:60-74 — store mutation hooks that trigger pushes:
  - :60 store.onSkipSetChanged = { _ in service.pushAll() }
  - :61 store.onShowUndatedRemindersChanged = { _ in service.pushAll() }
  - :62 store.onExcludedListsChanged = { _ in service.pushAll() }
  - :63 store.onCompleteReminder = { identifier in service.requestCompleteReminder(identifier) }
  - :68 store.onDeleteReminder = { identifier in service.requestDeleteReminder(identifier) }
  - :71-73 store.onSortOptionChanged = { option in SortOptionStore().save(option); service.pushAll() }
- AppViewModel.swift:77-81 — #if os(iOS) || os(macOS) widget hook: store.onRemindersChanged = { WidgetCenter.shared.reloadAllTimelines() }. This is the only macOS-relevant hook in the file.
- AppViewModel.swift:87-90 — #if os(iOS) setupSyncObservation(); setupEntitlementObservation() #endif.

### 1a. setupSyncObservation() — the AppGroup defaults observer

AppViewModel.swift:418-430:

    private func setupSyncObservation() {
        let center = NotificationCenter.default
        syncDefaultsObserver = center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: AppGroup.defaults,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.handlePreferencesChanged()
                }
            }
    }

- Token stored in syncDefaultsObserver: NSObjectProtocol? (AppViewModel.swift:459); doc at :412-417 states removal relies on token deallocation. No explicit NotificationCenter.removeObserver anywhere in the file.

### 1b. handlePreferencesChanged() — the diff that decides a push

AppViewModel.swift:432-449:

    private func handlePreferencesChanged() {
        let currentShowDate = ShowDatePreference().isEnabled
        let currentShowRecurrence = ShowRecurrencePreference().isEnabled
        let currentShowAlarms = ShowAlarmsPreference().isEnabled
        let currentShowList = ShowListPreference().isEnabled
        let currentShowCompletionGlow = ShowCompletionGlowPreference().isEnabled
        if currentShowDate != lastShowDate
            || currentShowRecurrence != lastShowRecurrence
            || currentShowAlarms != lastShowAlarms
            || currentShowList != lastShowList
            || currentShowCompletionGlow != lastShowCompletionGlow {
            lastShowDate = currentShowDate
            lastShowRecurrence = currentShowRecurrence
            lastShowAlarms = currentShowAlarms
            lastShowList = currentShowList
            lastShowCompletionGlow = currentShowCompletionGlow
            syncService?.pushAll()        // :448
        }
    }

- Only these five keys are diffed and pushed by this observer: showDate, showRecurrence, showAlarms, showList, showCompletionGlow (via ShowDatePreference() etc., all defaulting to AppGroup.defaults).
- Last-seen cache initialized eagerly at AppViewModel.swift:453-457 (lastShowDate = ShowDatePreference().isEnabled, ...).
- sortOption, showUndatedReminders, skip IDs, skip counts, excluded lists, completion count, and entitlement are NOT in this diff: they travel via the store hooks in §1 (:60-62, :71-73) and via setupEntitlementObservation.

### 1c. setupEntitlementObservation()

AppViewModel.swift:402-411 — withObservationTracking on store.entitlementStore.isEntitled; onChange calls self?.syncService?.pushAll() (:407) and re-registers itself by calling setupEntitlementObservation() again (:408), because the file comment says the SDK withObservationTracking returns Void.

### 1d. The @AppStorage write path that triggers the observer

All five show-* keys (plus undated and sort) are @AppStorage in SingleThread/ContentView.swift with store: AppGroup.defaults (:115-133: showUndatedReminders :115-116, sortOption :118-119, showDate :121-122, showList :124-125, showRecurrence :127-128, showAlarms :129-130, showCompletionGlow :132-133). The settings sheet edits these through the SettingsBindings snapshot bag (SingleThread/SettingsBindings.swift:18-45, writeback in SingleThread/ContentView+Settings.swift). Writing the suite fires UserDefaults.didChangeNotification on AppGroup.defaults → observer → pushAll().

- Crucially, the five show-* toggles have NO .onChange in ContentView; only the push via the defaults observer exists for them. showUndatedReminders and sortOption additionally have .onChange handlers: ContentView.swift:244-245 → ContentViewModel.handleShowUndatedReminders (ContentViewModel.swift:114-117, sets store.showsUndatedReminders whose didSet fires onShowUndatedRemindersChanged — ReminderStore.swift:134-137), and ContentView.swift:247-248 → handleSortOption (ContentViewModel.swift:119-121, store.setSortOption fires onSortOptionChanged — ReminderStore.swift:397-401, hook at :400). This is what triggers the store hooks at :61 and :71-73.
- AppGroup fallback: AppGroup.swift:20-22 — UserDefaults(suiteName: suiteName) ?? .standard.

### 1e. macOS

- setupSyncObservation / setupEntitlementObservation / the WCSession block / the syncService property are all inside #if os(iOS) (AppViewModel.swift:28-76, :87-90, :200-202). A macOS build takes none of the watch push paths. macOS only gets the widget-timeline hook (AppViewModel.swift:77-81).
- The macOS app still writes the same @AppStorage(store: AppGroup.defaults) keys (ContentView.swift:115-133 is platform-agnostic), but nothing on macOS pushes them to a watch.

## 2. Transport — SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift (compiled #if os(iOS) || os(watchOS), :3, :23)

### 2a. pushAll() snapshot (:176-213)

    public func pushAll() {
        do {
            var context: [String: Any] = [
                PayloadKey.skippedReminderIdentifiers: skipStore.load(),
                PayloadKey.skipCounts: countStore.load(),
                PayloadKey.excludedListTitles: excludeStore.load(),
                PayloadKey.showUndatedReminders: showUndatedStore.load(),
                PayloadKey.sortOption: sortStore.load().rawValue,
                PayloadKey.completionCount: completionCounter.count
            ]
            if sendsShowDate { context[PayloadKey.showDate] = showDateStore.isEnabled }
            if sendsShowRecurrence { context[PayloadKey.showRecurrence] = showRecurrenceStore.isEnabled }
            if sendsShowAlarms { context[PayloadKey.showAlarms] = showAlarmsStore.isEnabled }
            if sendsShowList { context[PayloadKey.showList] = showListStore.isEnabled }
            if sendsShowCompletionGlow { context[PayloadKey.showCompletionGlow] = showCompletionGlowStore.isEnabled }
            if sendsEntitled {
                let entitlement = entitlementStore
                context[PayloadKey.entitled] = MainActor.assumeIsolated { entitlement.isEntitled }
            }
            try session.updateApplicationContext(context)
        } catch { ... Self.logger.error ... }
    }

- Doc :171-175: "Pushes a complete snapshot of every synced setting as one latest-wins application context." updateApplicationContext = latest-wins, auto-delivers on (re)connect (doc :21-22).
- sends* flags are constructor params defaulting to true (:40-46), stored at :62-66 and :310-314. iOS passes sendsShowDate: true and sendsEntitled: true explicitly (AppViewModel.swift:39-40).
- Interactive requests use sendMessage instead: requestCompleteReminder (:219-226) and requestDeleteReminder (:230-237).

### 2b. PayloadKey enum (:278-293) — the exact wire strings

| Key constant | Value |
|---|---|
| skippedReminderIdentifiers | skippedReminderIdentifiers |
| skipCounts | skipCounts |
| excludedListTitles | excludedListTitles |
| completeReminderIdentifier | completeReminderIdentifier |
| deleteReminderIdentifier | deleteReminderIdentifier |
| showUndatedReminders | showUndatedReminders |
| sortOption | sortOption |
| showDate | showDate |
| showRecurrence | showRecurrence |
| showAlarms | showAlarms |
| showList | showList |
| showCompletionGlow | showCompletionGlow |
| completionCount | completionCount |
| entitled | isEntitled |

Doc :277-278: keys are shared by sender and receiver so the two sides of the wire protocol cannot drift.

## 3. Receive side — watch (SingleThreadWatch/)

### 3a. Entry point

SkippedReminderSyncService.swift:241-245 — session(_:didReceiveApplicationContext:) calls apply(context:).

apply(context:) (SkippedReminderSyncService.swift:320-376) — decode → persist → notify, per key; absent keys are no-ops:

- :329-332 skippedReminderIdentifiers → skipStore.save(receivedIDs) then onSkippedIdentifiersReceived
- :334-337 excludedListTitles → excludeStore.save(...) then onExcludedListTitlesReceived
- :339-342 showUndatedReminders → showUndatedStore.save(received) then onShowUndatedRemindersReceived
- :344-348 sortOption → sortStore.save(option) then onSortOptionReceived
- :350-353 showDate → showDateStore.set(showDate) then onShowDateReceived
- :355-358 showRecurrence → showRecurrenceStore.set(...) then onShowRecurrenceReceived
- :360-363 showAlarms → showAlarmsStore.set(...) then onShowAlarmsReceived
- :365-368 showList → showListStore.set(...) then onShowListReceived
- :370-373 showCompletionGlow → showCompletionGlowStore.set(...) then onShowCompletionGlowReceived
- :375 applyRemaining(context:)

applyRemaining(context:) (:381-395): skipCounts → countStore.save + onSkipCountsReceived (:382-385); entitled → onEntitlementReceived, persist intentionally skipped (EntitlementState is in-memory only) (:387-389); completionCount → onCompletionCountReceived (:391-394).

Doc :321-328: "Latest-wins ... the received values are authoritative. Replacing (rather than unioning) local values makes a clear update ([]) propagate."

didReceiveMessage (:247-256) handles the interactive completeReminderIdentifier / deleteReminderIdentifier messages → onCompleteReminderReceived / onDeleteReminderReceived (the phone registers these, not the watch).

### 3b. WatchAppViewModel.setupSyncService (SingleThreadWatch/WatchAppViewModel.swift:160-216)

- :161 guard WCSession.isSupported() else { return } — a standalone watch (no WCSession support) skips the service entirely.
- :163-173 — watch-side service built with sendsShowDate: false, sendsShowRecurrence: false, sendsShowAlarms: false, sendsShowList: false, sendsShowCompletionGlow: false, sendsEntitled: false (:172-173): the watch never pushes the show-* preferences or the entitlement back (one-way phone→watch). All its preference stores are pinned to .standard (:165-172) — on watchOS AppGroup.defaults falls back to .standard anyway (AppGroup.swift:20-22).
- Receive handlers wired before activate():
  - :176-181 onShowUndatedRemindersReceived → store?.showsUndatedReminders = value + store?.reload()
  - :185-188 onSkippedIdentifiersReceived → store?.reload() (skip store already persisted by apply)
  - :190-192 onSkipCountsReceived → store?.reload()
  - :194-196 onSortOptionReceived → store?.setSortOption(option)
  - :201-203 onCompletionCountReceived → AppGroup.defaults.set(count, forKey: "completionCount")
  - :206-208 onExcludedListTitlesReceived → store?.refreshExcludedListTitles(Set(titles))
- :209 service.activate(); :210 store.onSkipSetChanged = { _ in service.pushAll() } (watch→phone push for skip changes); :213-214 store.onCompleteReminder / onDeleteReminder relay via requestCompleteReminder / requestDeleteReminder.
- Comment at :204-205: "Exclusions sync phone→watch only: nothing on watch edits exclusions, so no push hook is wired here."

### 3c. wireStateReceiveHooks (WatchAppViewModel.swift:222-248)

    service.onShowDateReceived = { [weak showDateState] value in ... }           // :228-230
    service.onShowRecurrenceReceived = { [weak showRecurrenceState] value in ... } // :231-233
    service.onShowAlarmsReceived = { [weak showAlarmsState] value in ... }         // :234-236
    service.onShowListReceived = { [weak showListState] value in ... }             // :237-239
    service.onShowCompletionGlowReceived = { [weak showCompletionGlowState] value in ... } // :240-242
    service.onEntitlementReceived = { [weak entitlementState] value in ... }       // :244-246

Each closure hops through Task { @MainActor in ... } before calling .apply(value) on the state holder.

### 3d. Show*State @Observable holders (SingleThreadWatch/Show*.swift)

All five share the identical shape (verified ShowDateState.swift:1-31, ShowRecurrenceState.swift, ShowAlarmsState.swift, ShowListState.swift, ShowCompletionGlowState.swift):

    @Observable
    final class ShowDateState {
        init() {
            isEnabled = preference.isEnabled          // seeds from .standard
        }
        private(set) var isEnabled: Bool
        func apply(_ value: Bool) {
            preference.set(value)                      // persists
            isEnabled = value                          // publishes
        }
        private let preference = ShowDatePreference(defaults: .standard)   // ~:29
    }

- Each file doc states the holder replaces a former @AppStorage read-back whose observation of out-of-band UserDefaults writes was OS-version-dependent; updates now arrive through the sync pipeline explicit on*Received callback.
- EntitlementState (SingleThreadCore/Sources/SingleThreadCore/EntitlementState.swift:8-21) is the exception: @MainActor @Observable, apply only sets the in-memory isEnabled (default false); file doc: "Unlike the Show*State holders, this does NOT double-persist ... it only lives for the current process."

### 3e. Consumption on the watch

- WatchReminderView.swift:268 — if viewModel.showDateState.isEnabled, let due = display.dueDate (date line)
- WatchReminderView.swift:273 — if viewModel.showListState.isEnabled, let listName = display.listName
- WatchReminderView.swift:278 — if viewModel.showRecurrenceState.isEnabled, display.hasRecurrence
- WatchReminderView.swift:283 — if viewModel.showAlarmsState.isEnabled, display.hasAlarms
- WatchReminderViewModel.swift:86-87 — if await store.completeCurrentReminder(), showCompletionGlowState.isEnabled { ... completionGlow.trigger() ... } (glow gate)
- WatchReminderView.swift:246 — if !viewModel.store.canMutate, !viewModel.entitlementState.isEnabled { upgradeOniPhonePrompt } else { actionButtons } (freemium gate)
- Launch restore so the watch renders correctly before the first context push: WatchAppViewModel.swift:31 store.sortOption = SortOptionStore().load(); :34 store.showsUndatedReminders = ShowUndatedRemindersPreference(defaults: .standard).load(); the Show*State inits seed from .standard (§3d). Doc at :33: "Direct assignment fires the didSet hook, which is unwired on the watch — no echo."

## 4. Which preferences are watch-relevant today (inventory)

Computed from the push side (§1) and the receive side (§3) — the full pushAll() context key set is the universe:

1. showDate — key showDate — pushed by defaults-observer diff (AppViewModel.swift:433,438) — received by ShowDateState.apply (WatchAppViewModel.swift:228-230)
2. showRecurrence — pushed by observer diff (:434,439) — ShowRecurrenceState.apply (:231-233)
3. showAlarms — observer diff (:435,440) — ShowAlarmsState.apply (:234-236)
4. showList — observer diff (:436,441) — ShowListState.apply (:237-239)
5. showCompletionGlow — observer diff (:437,442) — ShowCompletionGlowState.apply (:240-242) → gates glow in WatchReminderViewModel.swift:87
6. Entitlement (paid) — key isEntitled — setupEntitlementObservation (:402-411) — EntitlementState.apply (in-memory only, EntitlementState.swift:16-19; wired WatchAppViewModel.swift:244-246)
7. showUndatedReminders — store hook onShowUndatedRemindersChanged (:61; fired from ReminderStore.swift:134-137 via ContentView.swift:244-245) — store.showsUndatedReminders + reload (WatchAppViewModel.swift:176-181)
8. sortOption — store hook onSortOptionChanged (:71-73; fired from ReminderStore.swift:397-401 via ContentView.swift:247-248) — store.setSortOption (WatchAppViewModel.swift:194-196)
9. skippedReminderIdentifiers — store hook onSkipSetChanged (:60; fired from ReminderStore.swift:595,610) — skipStore.save + store.reload() (WatchAppViewModel.swift:185-188)
10. skipCounts — part of every pushAll() (:180) — countStore.save + store.reload() (WatchAppViewModel.swift:190-192)
11. completionCount — part of every pushAll() (:184) — AppGroup.defaults.set(count, forKey: "completionCount") (WatchAppViewModel.swift:201-203) → feeds freemium gate WatchReminderView.swift:246
12. excludedListTitles — store hook onExcludedListsChanged (:62; fired from ReminderStore.swift:490) — excludeStore.save + store.refreshExcludedListTitles (WatchAppViewModel.swift:206-208)

The Apply() persistence target on the watch is .standard (the service stores and the Show*State holders are all constructed with defaults: .standard), which equals AppGroup.defaults by fallback (AppGroup.swift:20-22).

NOT watch-relevant: notificationsEnabled / notificationIntervalHours (iOS-only UserDefaults.standard, ContentView.swift:109-112), enableActionButtons, showSwipePrompt, showUndoButton, allowsLandscape, showMicrophoneButton, backgroundEnabled / backgroundFadePercent / backgroundPinned (ContentView.swift:72-107) — none appear in the sync payload or in any watch state holder.

## 5. Launch-arg seams that simulate a preference being on/off when the watch runs standalone

### Watch seams (SingleThreadWatch/WatchAppViewModel.swift)

- --ui-testing (:14) — deterministic single-reminder store without EventKit auth (uiTestingStore, :95-149; buys groceries, priority 5).
- --ui-testing-gated (:21-27) — seeds the local completion counter at the cap: AppGroup.defaults.set(EntitlementStore.freemiumCap, forKey: "completionCount"), so store.canMutate is false and WatchReminderView.swift:246 renders upgradeOniPhonePrompt (test at SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift:180-195).
- --ui-testing-glow (:50-51) — showCompletionGlowState.apply(true) force-enables the glow preference (launched .standard may hold false from an earlier test run in the same session); also sets isGlowUITesting (:53) and extends reminderViewModel.completionGlow.duration = 2.0 (:55-57). On the phone the same flag extends the glow in AppViewModel.makeContentViewModel (AppViewModel.swift:243-246) and exposes the overlay to accessibility (ContentView.swift:313-316, :581-589; WatchReminderView.swift:71-72, :178).
- --ui-testing-glow-disabled (:48-49) — showCompletionGlowState.apply(false) pre-disables the state so the disabled-flow test needs no settings screen.
- --ui-testing-priority <n> (:107-110) — overrides the sample reminder priority (test :26-35).
- --ui-testing-skip-count <n> (:118-121) — seeds skipCounts into AppGroup.defaults (fallback .standard) so the 6th-skip nudge is one tap away (test :108-140).
- --ui-testing-excluded-list "<list>" (:131-146) — gives the sample reminder a calendar of that title AND pre-populates the store exclusion set (card suppressed; test :40-54).
- --ui-testing-live-excluded "<list>" (:131-146 + :252-263) — gives the calendar but an empty exclusion set; scheduleUITestLiveExcludedDelivery calls service.session(WCSession.default, didReceiveApplicationContext: ["excludedListTitles": [list]]) 5 seconds after launch (:255-262), proving the receive path applies a context live (test :59-74).

Watch UI-test usage: SingleThreadWatchUITestsFlows.swift launchApp() defaults to ["--ui-testing"] (:190-195); flag usage at :27, :41, :60, :110, :183, :203. Unit tests pin the seams: SingleThreadWatchTests/ShowCompletionGlowStateTests.swift:46-61 (parameters ("--ui-testing-glow-disabled", false) and ("--ui-testing-glow", true); it seeds a persisted false first to prove the flag overrides it) and SingleThreadWatchTests/WatchAppViewModelTests.swift:26-34 (completionGlow.duration == 2.0).

### iOS seams of the same family (SingleThread/AppViewModel.swift)

- --ui-testing (:281-312) — mirrors the watch seam: single Buy-groceries store, sets UserDefaults.standard value for enableActionButtons = true (:290).
- --reset-glow-preference (:285-286) — UserDefaults.standard.removeObject(forKey: "showCompletionGlow"); used at SingleThreadUITests/SingleThreadUITestsFlows.swift:426.
- --reset-swipe-preference (:288-289) — removes showSwipePrompt; used at SingleThreadUITests.swift:29-32 and SingleThreadUITestsFlows.swift:518,530,557.
- --ui-testing-glow (:243-246) — glow duration 2.0 s; used with --seed at SingleThreadUITestsFlows.swift:469,496.
- --seed "<json>" (UITestingSeed.fromLaunchArguments, SingleThreadCore/.../UITestingSeed.swift:48-59) — in-memory store; writes completionCount and skipCounts into AppGroup.defaults (AppViewModel.swift:297-300); supports isEntitled / entitlementUnresolved / excludedLists / hasHidden (UITestingSeed.swift:138+); resetPersistedState removes all keys in the persistedKeys list (UITestingSeed.swift:62-71, list at :73-99) so nothing leaks between launches.

Note: the app-level default registration UserDefaults.standard.register(defaults: ["showMicrophoneButton": true]) (AppViewModel.swift:205-208) does not cover any synced preference — those live in AppGroup.defaults and resolve via object(forKey:) as? Bool ?? default inside the Core structs (e.g. ShowDatePreference.swift:17-20 nil → true; ShowListPreference.swift:17-20 nil → false).

## 6. Key causal chain

- Toggle write → @AppStorage(store: AppGroup.defaults) (ContentView.swift:121-133) → UserDefaults.didChangeNotification on the suite → setupSyncObservation observer (AppViewModel.swift:420-426) → handlePreferencesChanged() diff (:432-449) → syncService?.pushAll() (:448).
- pushAll() (SkippedReminderSyncService.swift:176-213) builds one combined context (PayloadKey.*, :278-293) → session.updateApplicationContext → auto-delivered to the paired watch.
- Watch session(_:didReceiveApplicationContext:) (:241-245) → apply (:320-376) persists each present key into the .standard-backed stores, then fires on*Received → wireStateReceiveHooks (WatchAppViewModel.swift:222-248) → Show*State.apply persists again and publishes (ShowDateState.swift:18-22) → views re-render (WatchReminderView.swift:268-283).
- Standalone watch (no WCSession support): the service is skipped (guard WCSession.isSupported(), WatchAppViewModel.swift:161); preferences render from .standard seeds at launch (:31, :34, Show*State inits), which is exactly what the --ui-testing-glow* seams override.

## 7. Residual risks / gaps

- The SkippedReminderSyncService.swift:127-162 region (onEntitlementReceived, onCompletionCountReceived, onSkippedIdentifiersReceived, onSkipCountsReceived, onSortOptionReceived property declarations) was verified by reading the file; per-property line numbers are cited as ranges where grep did not confirm the individual line.
- This question scope is iOS→watch only; widget behavior (same App Group keys read directly, AppGroup.swift:11-14) is not covered.
- --ui-testing-glow-disabled exists only in the watch target and its unit tests; iOS has --reset-glow-preference instead.
