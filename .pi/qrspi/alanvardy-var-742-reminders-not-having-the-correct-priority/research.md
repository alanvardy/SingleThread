# Research Findings

Branch: `alanvardy-var-742-reminders-not-having-the-correct-priority`
Commit verified against: working tree (all line numbers verified against current files)

## Q1: Fetch path: EKReminder → in-app model

### Findings
- **There is no intermediate model.** `ReminderStore.reminders: [EKReminder]` caches the raw EventKit objects fetched from the store (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:43`); the fetch result is assigned wholesale at `ReminderStore.swift:322` (`reminders = shown`). The `@MainActor @Observable` store is the durable in-memory model.
- The only "display model" is `ReminderDisplay`, a transient value snapshot built per render (widget timeline, tests, views); it is never stored back: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:8-21`.
- **Single mapping point:** `ReminderDisplay.init(reminder:)` (`ReminderDisplay.swift:11-21`). Property-by-property:
  - `title` → `title: String` (`ReminderDisplay.swift:12, 44`)
  - `notes` → `ReminderNotesFormatter.format` strips the known leading `"t"` artifact, trims, returns `nil` for empty (`ReminderDisplay.swift:13`; `ReminderSkip.swift:103-119`)
  - `dueDateComponents?.date` → `dueDate: Date?`; timezone/component breakdown dropped (`ReminderDisplay.swift:14, 46`)
  - `priority` (Int) → `priorityMarker: String` via `ReminderPriority.marker(for:)` (`ReminderDisplay.swift:15, 47`; `ReminderSkip.swift:71-80`). **The raw Int is discarded — only the marker string survives**; `""` when none.
  - `calendar?.title` → `listName` (`ReminderDisplay.swift:16, 48`); calendar identity otherwise dropped
  - `hasRecurrenceRules` → Bool (`:17`); `recurrenceRules` → first-rule-only summary via `ReminderRecurrenceFormatter` (`:18, 50`); `hasAlarms` → Bool (`:19, 51`)
- **Never-read `EKReminder` properties (dropped end-to-end in all paths):** `url`, `location`, `startDateComponents`, `completionDate`, `lastModifiedDate`, `timeZone`, `contactIdentifier`, `endDateComponents`, alarm details, recurrence rules beyond the first. (No references anywhere in `SingleThread/`, `SingleThreadCore/`, `SingleThreadWatch/`.)
- **Priority semantics:** EventKit uses the CalDAV scheme — `0` = none, `1` = high, `5` = medium, `9` = low (`ReminderSkip.swift:26-29` doc). `EKReminder.priority` is a non-optional `Int`; a fresh reminder defaults to `0`, so "unset" is the value `0` in this app (`marker(for: 0)` ⇒ `""`, `ReminderSkip.swift:54-58, 71-80`). Any other Int (e.g. `3`) also maps to "none".
- **All load paths funnel through one function,** `ReminderStore.reload(clearSkipped:)` (`ReminderStore.swift:287-346`):
  - initial load: `start()` (`:141-161`) → checks `authorizationStatus`; `.fullAccess` ⇒ `reload()`, else `requestAccess()` (`:369-381`) → `reload()` on grant
  - `refreshSourcesIfNecessary()` before fetch (`:291`); predicate `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:nil)` (`:301-304`); window filter via `ReminderDateFilter` when `showsUndatedReminders` (`:305-307`; `ReminderDateFilter.swift:43-76`)
  - `hasHidden` computed via a second broad fetch when not showing undated (`:309-320`; `hasHiddenFor` at `:133-139`)
  - `availableLists` from `eventStore.calendars(for: .reminder)` (`:323-327`)
  - `skippedIDs` re-resolved + re-persisted from persisted store (`:333-340`)
  - `onRemindersChanged?()` fired (`:345`)
- **Caching/invalidation:** no separate cache layer — `reload()` replaces `reminders` wholesale; visibility filtering/sorting happens on read via the computed `visibleReminders` (`:111-118`).
- `EKReminder` is retroactively declared `@unchecked Sendable` to cross the fetch continuation boundary (`ReminderDateFilter.swift:20-26`).

## Q2: Skip mechanism end-to-end

### Findings
- **Persistence:** `SkippedReminderStore` (`ReminderSkip.swift:121-138`) stores a `[String]` of `EKReminder.calendarItemIdentifier` values in `UserDefaults` under the literal key `"skippedReminderIdentifiers"` (`:124`), backed by the App Group suite `"group.app.alanvardy.SingleThread"` with `.standard` fallback (`AppGroup.swift:4-16`). Same suite is shared with the widget (`AppGroup.swift:4-6` doc).
- **Recorded at these gesture/button sites** (all funnel into `ReminderStore.skipCurrentReminder()`, `ReminderStore.swift:253-260`):
  - iOS trailing-edge swipe: `ContentView.swift:380-383`
  - iOS bottom-bar Skip button (gated by `showsActionButtons`): `ContentView.swift:462-469`, cluster `:474-479`; gate at `ContentViewModel.swift:39-42`
  - macOS `s` keyboard shortcut: `ContentView.swift:255-265` (`actionButtons`)
  - watchOS Skip button: `SingleThreadWatch/WatchReminderView.swift:116-126`
  - Widget `SkipReminderIntent` → `skipCurrentReminderImmediately()` (writes synchronously — safe for WidgetKit suspension): `ReminderIntents.swift:30-51`, `ReminderStore.swift:279-285`; button at `SingleThreadWidget/NextThingWidget.swift:166-176`
- **Code path:** `ContentViewModel.skipCurrentReminder()` (`ContentViewModel.swift:118-120`) → `store.skipCurrentReminder()`: guards `canMutate` (`:254`; `canMutate` = entitled OR counter < 100, `:126-129`), takes `visibleReminders.first` (`:255`), computes `updatedSkipSet(afterSkipping:)` (`:397-400` → `ReminderSkipLogic.skipping` `ReminderSkip.swift:19-23` → `resolve` pruning stale IDs `:12-15`), then applies inside a `Task` after a 200 ms EventKit settle sleep (`:257-260`).
- **Apply:** `applySkipSet` (`ReminderStore.swift:405-409`) sets `skippedIDs`, persists via `skipStore.save`, fires `onSkipSetChanged` (watch push) and `onRemindersChanged` (widget reload).
- **Cleared** only by `reload(clearSkipped: true)`: resets `skippedIDs = []` and saves `[]` (`ReminderStore.swift:328-331`). Triggered by pull-to-refresh in the "All Done" state on iOS (`ContentView.swift:304-316`, calling `viewModel.reload(clearSkipped: true)`), and by the watch Refresh button (`WatchReminderViewModel.swift:89-104`).
- **Stale-entry cleanup:** every `reload()` re-runs `ReminderSkipLogic.resolve(fetched:skipped:)` (`ReminderStore.swift:333-340`) and re-saves the pruned list, so a completed/deleted-while-skipped reminder's ID drops from persistence automatically.
- **Re-entry into the visible list:** skipping only filters via `!skippedIDs.contains($0.calendarItemIdentifier)` (`ReminderStore.swift:113`); a skipped reminder reappears only when `clearSkipped` reload runs.
- **No EKReminder mutation:** the skip path touches only the identifier set — it never re-fetches, rewrites, or re-saves the `EKReminder` or any in-memory representation beyond the set (verified: `skipCurrentReminder` / `applySkipSet` / `updatedSkipSet` bodies contain no `eventStore` or property write).

## Q3: Reminder creation paths

### Findings
- **Only production creation flow is voice dictation** (iOS/macOS):
  - UI triggers: `micButton` (`ContentView.swift:490-495`), bottom bar (`:421-443`), `actionCluster` (`:474-479`)
  - `DictationViewModel.startDictation()` (`SingleThread/DictationViewModel.swift:32-66`): authorizes (`:34-42`), transcribes (`:48`), parses with `ReminderDictationParser` (`:51`), then calls the store only when the parsed title is non-empty (`:52-58`):
    `store.addReminder(title: parsed.title, notes: nil, dueDate: parsed.dueDateComponents, recurrenceRule: parsed.recurrenceRule)`
  - `ReminderStore.addReminder` (`ReminderStore.swift:228-248`): returns `false` on watchOS (`:233-235`); otherwise `eventStore.makeReminder(...)` → `save(commit: true)` → 200 ms settle → `reload()` → `true`
  - Real factory `EKEventStore.makeReminder` (`EventKitStoring.swift:51-64`): sets only `title`, `notes`, `dueDateComponents`, optional `recurrenceRule`, `calendar = defaultCalendarForNewReminders()`. **No priority, no alarms, no completion date.**
  - Parser output shape: `Result(title:dueDateComponents:recurrenceRule:)` (`ReminderDictationParser.swift:26-35`) — **the parser has no priority concept.**
- **Defaults for unset properties:** a fresh `EKReminder` created this way has `priority == 0` (none). **No production creation path sets priority** — every `priority =` assignment in the codebase is a test/preview/seam site: `AppViewModel.swift:154` (`--ui-testing` seam), `ContentView.swift:582` (preview mock), `WatchAppViewModel.swift:100` (`--ui-testing` seam), `WatchReminderView.swift:282,291` (previews), `UITestingSeed.swift:121-122` (UI-test seed).
- **UI-test seeding (`--seed '<json>'`):**
  - `UITestingSeed.fromLaunchArguments` (`UITestingSeed.swift:18-26`); JSON schema doc `:8-17`, `ReminderSeed` fields `title`/`notes`/`priority?` (`:95-99`) — no due date, recurrence, or alarms
  - `materialize()` (`:112-130`): builds `EKReminder` with title, notes, `priority` only when present (`:121-122`), `calendar` = first seeded calendar title (`:124`)
  - Wiring: `AppViewModel.makeStore` (`AppViewModel.swift:123-126`) → `seededStore` (`:172-199`): calls `UITestingSeed.resetPersistedState()` (`UITestingSeed.swift:31-50`), wraps reminders in `InMemoryEventStore` (`InMemoryEventStore.swift:24-33`), writes `completionCount` + entitlement, enables `enableActionButtons`
- **Entry into the visible list:** creation ends with `reload()` (`ReminderStore.swift:242-243`) → the new reminder is fetched back into `reminders` and immediately subject to `visibleReminders` filtering (skip/exclusion: `:113-114`) and sorting (`:115`). Require it be incomplete and inside the date window (`ReminderDateFilter`).

## Q4: iOS presentation of priority

### Findings
- **No dedicated view-model layer holds priority.** The chain is: `ReminderStore` (raw `EKReminder`, `:43`) → `ReminderDisplay` value snapshot → `ReminderCardView`:
  - `ContentViewModel` holds `let store` and never reads/writes priority (`ContentViewModel.swift:41`); `AppViewModel` is the composition root (`AppViewModel.swift:12-19`)
  - `ReminderCardView` captures `private let display: ReminderDisplay` (`ReminderCardView.swift:109`)
  - `ReminderDisplay` is **recreated on every `ContentView.body` render** from `viewModel.store.visibleReminders.first` at `ContentView.swift:337-338`; `ReminderDisplay.init` re-reads `reminder.priority` at snapshot time (`ReminderDisplay.swift:15`)
- **Rendering (iOS):** in the title row, if `ReminderPriority.level(forMarker:)` yields a level, a `Text(display.priorityMarker)` (`"!!!"`/`"!!"`/`"!"`) is shown in `.font(.title)` with `priorityColor(level)` — high red, medium yellow, low green — plus an accessibility label `"<level> priority"` (`ReminderCardView.swift:90-96`; color map `:171-177`).
- **Transformation between model and display:** raw Int → `Level?` (`ReminderSkip.swift:50-58`) → marker string (`:71-80`) → UI color + a11y name. Only `1/5/9` map to levels; `0` and anything else yield `nil`/empty and render nothing.
- **Ordering:** `sortOption` defaults to `.priority` (`ReminderStore.swift:75`; `SortOption.swift:6-9`); `ReminderSort.areInIncreasingOrder` for `.priority` applies the legacy compound order priority → due date → title (`ReminderSort.swift:10-13, 14-30`), comparing raw priorities through `ReminderPriority.rank` (`ReminderSort.swift:46-59`; `ReminderSkip.swift:82-90` — high 0 < medium 1 < low 2, no-priority sorts last). Due-date (`.dueDate`) and title (`.title`) modes ignore priority.
- **No priority-based filtering** anywhere in the iOS path.
- Priority is never written back to an `EKReminder` in production code (see Q3 for the only assignment sites).

## Q5: WatchOS data acquisition and presentation

### Findings
- **The watch fetches reminder data directly from EventKit on-device — the phone transmits no reminder content.** WatchConnectivity payload keys (`SkippedReminderSyncService.swift:268-287`) carry only skip IDs, excluded-list titles, show-* preferences, sort option, completion count, and entitlement — there is no key for title/notes/priority/due date/list/recurrence/alarms.
- Watch store construction: `SingleThreadWatchApp.init` → `WatchAppViewModel()` (`SingleThreadWatchApp.swift:8-16`) → `ReminderStore(loadsReminders: true)` in production (`WatchAppViewModel.swift:13-19`), backed by a real `EKEventStore` (`ReminderStore.swift:15`); `store.start()` from the view's `.task` (`WatchReminderViewModel.swift:57-59`) exercises the same authorization → `reload()` path as iOS (`ReminderStore.swift:141-161, 287-346`). The watch target declares its own `NSRemindersFullAccessUsageDescription` in the pbxproj.
- Only `--ui-testing` launches use the in-memory seam: `WatchAppViewModel.uiTestingStore` (`WatchAppViewModel.swift:96-133`) builds `InMemoryEventStore` with a single reminder (`priority = 5`, `:100`) and `loadsReminders: false`.
- **Priority on the watch:** `ReminderDisplay.init(reminder:)` built inside the card render (`WatchReminderView.swift:190-196`); rendered identically to iOS — marker `Text` + `priorityColor` (green/yellow/red) + a11y label, via `ReminderPriority.level(forMarker:)` (`WatchReminderView.swift:220-229, 263-267`).
- **Completion/transition ghost card:** `transitionReminder: EKReminder?` snapshot (`WatchReminderViewModel.swift:51`) is captured from `store.visibleReminders.first` before completing (`:67`), rendered while `isShowingCompletionTransition` (`WatchReminderView.swift:79-81`), and cleared after `completionGlow.duration + completionTransitionBuffer` (`WatchReminderViewModel.swift:72-86`). **The snapshot is only read for display — it is never written back, re-fetched, or re-saved.** In fact, on watchOS the store removes the reminder locally and forwards the completion to the phone via `onCompleteReminder`; it never performs an EventKit write (`ReminderStore.swift:168-179`).

## Q6: iPhone↔Watch synchronization of skipped identifiers

### Findings
- **Single transport:** `SkippedReminderSyncService` (`SkippedReminderSyncService.swift:24`), compiled only under `#if os(iOS) || os(watchOS)` (`:23`); `WCSession` hidden behind the `SkipSyncSession` protocol (`:8-17`). Two channels: `updateApplicationContext` for state (latest-wins, auto-delivers on reconnect — class doc `:19-22`) and `sendMessage` for watch→phone Complete/Delete commands (`:210-228`). No `transferUserInfo`/`sendMessageData` anywhere.
- **Who pushes / who applies:**
  - iPhone pushes a **full combined context** on every synced-state mutation: `store.onSkipSetChanged` → `pushAll()` and `onShowUndatedRemindersChanged`/`onExcludedListsChanged`/`onSortOptionChanged` → `pushAll()` (`AppViewModel.swift:56-70`); entitlement changes via `withObservationTracking` (`:208-221`); show-* preference diffs via a `UserDefaults.didChangeNotification` observer on `AppGroup.defaults` (`:224-255`). Guarded by `WCSession.isSupported() && !usesInMemoryStore` (`:27`); service built with `sendsShowDate: true`/`sendsEntitled: true`, all other sends default `true` (`SkippedReminderSyncService.swift:31-42, 39-44`).
  - Watch pushes **only its own skip-set changes**: `store.onSkipSetChanged = { _ in service.pushAll() }` (`WatchAppViewModel.swift:184`); built with all `sends*: false` (`WatchAppViewModel.swift:151-171`) so its `pushAll()` sends only the five always-on keys. It applies every incoming key through receive hooks (`:145-183`): show-undated → set + `reload()`, skipped IDs → `reload()` (re-reads the just-persisted set, `:164-166`), sort → `setSortOption`, completion count → writes `AppGroup.defaults`, exclusions → `refreshExcludedListTitles`, show-* / entitlement → state holders (`wireStateReceiveHooks` `:196-223`).
- **Sync payload:** `pushAll()` builds one context from the stores: `skippedReminderIdentifiers`, `excludedListTitles`, `showUndatedReminders`, `sortOption`, `completionCount`, plus gated show-*/entitled keys (`SkippedReminderSyncService.swift:167-208`). Receive: `session(didReceiveApplicationContext:)` → single `apply(context:)` path: decode → persist → notify for each present key (`:308-367`); missing keys are no-ops. **Replacement, not union** — explicitly documented so a "clear" (`[]`) propagates (`:311-314`).
- **Refresh timing:** each side activates once at app launch (`AppViewModel.swift:27` / `WatchAppViewModel.swift:140`). There is **no** `sessionWatchStateDidChange` or `sessionReachabilityDidChange` handler — re-connect delivery is relied on rather than coded (`:19-22`); `activationDidCompleteWith` only logs (`:249-256`); iOS `sessionDidDeactivate` re-activates (`:258-259`). In-memory `skippedIDs` refreshes only via `reload()`.
- **Conflict/staleness model:** latest-wins full-set replacement (sender's context is authoritative, `:308-314`); stale IDs are pruned on the next `reload()` by `ReminderSkipLogic.resolve` (`ReminderStore.swift:333-340`). No timestamps, no merge, no versioning.

## Q7: Test coverage of priority and skip behavior

### Findings
- **Priority mapping** — `struct ReminderPriorityTests` (`SingleThreadTests/ReminderSkipTests.swift:98-142`): `levelMapsHighPriority` (:100, `1→.high`), `levelMapsMediumPriority` (:105), `levelMapsLowPriority` (:110), `levelIsNilForNoPriority` (:115, `0→nil`), `levelIsNilForUnknownPriority` (:120, `3→nil`), `markerIsTwoForMedium` (:125, `5→"!!"`), `markerIsThreeForHigh` (:130, `1→"!!!"`), `markerIsOneForLow` (:135), `markerIsEmptyWhenNoPriority` (:140).
- **Display mapping** — `struct ReminderDisplayTests` (`ReminderDisplayTests.swift`): `mapsHighPriorityMarker` (:54-57, priority 1 → `"!!!"`), `mapsEmptyMarkerForNoPriority` (:61-64, 0 → empty), `directConstructorCreatesFields` (:121-133, round-trips `priorityMarker: "!"`).
- **Sorting** — `struct ReminderSortTests` (`ReminderSkipTests.swift:237-321`): `sortsHighPriorityBeforeLow` (:241), `sortsHighBeforeMediumBeforeLow` (:248), `sortsPrioritizedBeforeNoPriority` (:256), same-priority-by-date (:263), dated-before-undated (:270), alphabetical tie-break (:277), `priorityOptionMatchesLegacyComparator` (:286), plus due-date/title mode tests (:296-321). Fixture `makeReminder(title:priority:)` builds bare `EKReminder`s on a throwaway `EKEventStore` (:326-340).
- **Store-level** — `ReminderStoreTests.swift`: `visibleRemindersFiltersOutSkippedIDs` (:11-24), `visibleRemindersEmptyWhenAllSkipped` (:26), `visibleRemindersSortsByPriority` (:49-62), `visibleRemindersSortsDatedBeforeUndated` (:63-78), `setSortOptionReordersVisibleReminders` (:177-195, default `.priority`), `addReminderWithInMemoryStoreDoesNotCrash` (:234).
- **Skip logic** — `struct ReminderSkipLogicTests` (`ReminderSkipTests.swift:7-95`): `resolve` prunes stale IDs (:11), keeps valid (:17), empties (:23,29,35,41); `skipping` adds/prunes/dedupes (:57-94). Gating + async apply covered in `ReminderStoreGateTests.swift:78-121` (skip is no-op when gated; skip applies inside a `Task`).
- **Sync service** — `SkippedReminderSyncServiceTests.swift` (fake `SkipSyncSession`): `pushAllSendsSkipIDs` (:52), `pushAllSendsFullFiveKeyShape` (:77), `receiveContextFiresSkippedIdentifiersHandlerAfterPersisting` (:161), `receiveContextReplacesLocalIDs` (:193), `receiveContextClearPropagates` (:209), empty/malformed payloads (:224, :235), completion request/relay (:282-304).
- **Seed seam** — `UITestingSeedTests.swift`: `parsesRemindersFromCompactJSON` (:12-25, includes `"priority":1` round-trip at :23), `parsesCalendarsAndExcludedLists` (:27), `completionCountAndIsEntitled` (:39), defaults when absent (:51), malformed → nil (:63), `inMemoryStoreRendersSeededRemindersThroughStore` (:71). Store side: `InMemoryEventStore` returns all non-completed reminders (`InMemoryEventStore.swift:55-56`) and reports `.fullAccess` (`:40-42`).
- **UI tests** — `SingleThreadUITestsFlows.swift` (XCTest, `--seed` seam): `testListShowsSeededReminder` (:31), `testSkipAdvancesToNextReminder` (:53-70) — seeds priorities 1 and 9 and **asserts the high-priority reminder is shown first, then that Skip advances to the next**; `testSkipAllShowsAllDoneState` (:73); complete/delete via swipe/context menu (:90-125). `ActionButtonsUITests.testActionButtonsRenderAndSkipAdvancesCard` (:20). No UI test asserts the rendered marker string itself. Watch UI tests drive the `--ui-testing`/`--ui-testing-glow` seams (`WatchAppViewModel.swift:96-133`).

## Cross-Cutting Observations
- **`EKReminder` is the universal in-memory model** on both platforms; `ReminderDisplay` is only a per-render snapshot used by views, the widget timeline, and tests. Nothing maps reminders into a durable DTO.
- **Priority has two independent consumers of the same raw Int:** display (`ReminderPriority.marker`, `ReminderSkip.swift:71-80`) and sorting (`ReminderPriority.rank`, `:82-90`). Both recognize only `1/5/9`; every other value (including `0`) is "none".
- **The skip list is identifier-only** and never touches `EKReminder` objects; its lifecycle is record (gesture/button/intent) → persist → push; clear (refresh with `clearSkipped`) and prune (every `reload()`).
- **WatchConnectivity carries state, never content:** the watch reads EventKit itself and the wire protocol contains no reminder fields (`SkippedReminderSyncService.swift:268-287`); skips and commands are identifier-level.
- **All mutations gate on `canMutate`** (entitled OR completion count < 100, `ReminderStore.swift:126-129`); completion of the watch/phone relay path only ever forwards identifiers.
- **Two deterministic test seams:** iOS `--seed '<json>'` (rich multi-reminder seeding incl. priority, `UITestingSeed.swift:8-17`) and both platforms' `--ui-testing` (single reminder, `priority = 5`).
- **Seams and previews are the only places priority is ever written** (grep for `priority =`); the dictation creation path and real `makeReminder` factory never set it, so every created reminder is priority 0.
- Same App Group `UserDefaults` key family is read across phone, watch, and widget (`skippedReminderIdentifiers`, `sortOption`, `show*`, `completionCount`).

## Open Areas
- No UI test asserts the visible priority marker text or its color/accessibility label on either platform; only ordering (`testSkipAdvancesToNextReminder`) and unit-level mapping are covered.
- The freemium/counter interaction with priority gating was not deeply traced beyond `canMutate`; not priority-related.
- `EKReminder.priority` values outside the CalDAV set (e.g. 2-4, 6-8) are documented as "unknown" by tests but there is no evidence of how a real Reminders.app-created reminder with such a value renders beyond the nil branch.
- Whether Reminders.app itself ever writes priorities other than 0/1/5/9 to the store is not observable from this codebase (EventKit writes are read-only via API here).