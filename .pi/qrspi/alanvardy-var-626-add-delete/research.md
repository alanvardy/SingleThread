# Research Findings

Codebase root: `/Users/vardy/dev/alanvardy-var-626-add-delete`
All paths below are relative to that root. `file:line` references use the symbol's
definition site unless a call site is explicitly noted.

---

## Q1: Write and removal operations on the EventKit seam, mapped to reminder lifecycle

### Findings

- `EventKitStoring` is a `@MainActor` protocol (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:8`) that is the **only** EventKit surface `ReminderStore` touches. It exposes:
  - `authorizationStatus(for:)` EventKit:11 — instance wrapper over `EKEventStore.authorizationStatus`.
  - `calendars(for:)` :13 — reminder calendars, used for the project list.
  - `requestFullAccessToReminders()` :15 — full-access prompt.
  - `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` :16 — builds the fetch predicate.
  - `fetchReminders(matching:completion:)` :22 — async completion-handler fetch.
  - `#if !os(watchOS)` block (:27–35) gates three **write ops** behind non-watch targets:
    - `refreshSourcesIfNecessary()` :27.
    - `save(_ reminder: EKReminder, commit: Bool) throws` :29 — **the only write primitive**.
    - `makeReminder(title:notes:dueDate:recurrenceRule:)` :33 — constructor factory.
- `extension EKEventStore: EventKitStoring` :41 supplies the production impl. `makeReminder` (:47) builds `EKReminder(eventStore: self)`, sets `title`, `notes`, `dueDateComponents`, calls `addRecurrenceRule(_:)` for a non-nil rule (:57), and sets `calendar = defaultCalendarForNewReminders()` (:59). Authorization/`save`/`fetchReminders` aren't overridden — they bind to `EKEventStore`'s own methods via the extension.
- **Reminder lifecycle write sites** (all in `ReminderStore`):
  - `completeReminder(identifier:)` (:121): `#if os(watchOS)` removes the item from the local array only (`reminders.removeAll { … == identifier }`, :123) and fires `onCompleteReminder`. Elsewhere: `guard let ... first(where:)` (:127), sets `reminder.isCompleted = true` (:128), `eventStore.save(reminder, commit: true)` (:129), settles 200 ms (:130), `reload()` (:131). So "complete" is a **mutate-and-save**, never a delete.
  - `addReminder(title:notes:dueDate:recurrenceRule:) -> Bool` (:148) calls `eventStore.makeReminder` (:153), `save(reminder, commit: true)` (:162), settles (:163), `reload()` (:164), returns Bool. watchOS bails to `false` (:190).
  - `fetchReminders(bridge)` (:307) wraps EventKit's completion-handler API in `withCheckedContinuation`/`CheckedContinuation<[EKReminder], Never>`.
- **No removal/delete operation exists on the seam.** `grep` for `delete|seder|removal|removeAll` in `SingleThreadCore`/`SingleThread`/`SingleThreadWatch`/`SingleThreadWidget` returns only: the watchOS in-array `removeAll` (ReminderStore.swift:123), parser string `.removeSubrange`/`.removeLast()` (ReminderDictationParser.swift:288,298,350,354), audio `inputNode.removeTap` (ReminderDictation.swift:127), and doc-comment "REMOVAL PLAN" notes. There is **no** `EKEventStore.deleteRecurrenceScope`. The seam has no removal counterpart to `save`.
- **Recurring reminders under a hypothetical removal:** `makeReminder` adds the rule via `addRecurrenceRule` (EventKit:57), producing `reminder.recurrenceRules` (count 1) and `hasRecurrenceRules = true` (asserted ReminderStoreTests.swift:429, :418). Because the seam only exposes `save` (not EventKit's remove), a recurring item is written as one persisted series object; the codebase has no path that would delete a series or a single recurrence instance, so recurrence behavior "under removal" is currently unreachable through the code — no existing removal semantics exist to describe.

---

## Q2: How the current reminder is surfaced and acted upon per surface

**Findings**

- `ReminderStore.visibleReminders` (ReminderStore.swift:95–101) is the single source of "current." It filters `reminders` by `!skippedIDs.contains(calendarItemIdentifier)` and `!excludedProjectTitles.contains(calendar?.title ?? "")`, then sorts with `ReminderSort.areInIncreasingOrder($0,$1,using: sortOption)`. Every surface consumes it via `.first`:
  - `completeCurrentReminder()` ReminderStore.swift:138 — `visibleReminders.first`.
  - `skipCurrentReminder()` :173 and `skipCurrentReminderImmediately()` :198 — `visibleReminders.first`.
  - Widget + watch + iOS render only `store.visibleReminders.first`.
- **iOS (`SingleThread/ContentView.swift`):**
  - The card is `ReminderCardView(reminder: store.visibleReminders.first, showDate:)` (ContentView.swift:286), `.padding(40/12)`, `.listRowSeparator(.hidden)`.
  - iOS-only `.contextMenu` (:277): one Button "View in Reminders" (`systemImage:"eye"`) — builds `ReminderDeepLink.url` for the identifier and `openURL` (ContentView.swift:278–286; `ReminderDeepLink.url` builds `x-apple-reminderkit://REMCDReminder/<id>`, ReminderDeepLink.swift:15).
  - `.swipeActions(edge: .leading)` (:289): Button label `Label("Complete", systemImage: "checkmark.circle.fill")`, `Task { await store.completeCurrentReminder() }` (:291), `.tint(.green)`.
  - `.swipeActions(edge: .trailing)` (:297): Button `Label("Skip", systemImage: "circle.slash")`, `store.skipCurrentReminder()` (:299), `.tint(.orange)`.
  - `bottomBar` (`VStack`), and on macOS it conditionally shows `actionButtons` when `store.visiblePresent.first != nil` (ContentView.swift:318–320).
- **macOS:** `actionButtons` HStack (ContentView.swift:191–215): Complete Button `Label("Complete", systemImage:…fill")`, `Task { await store.completeCurrentReminder() }`, `.tint(.green)`, `.keyboardShortcut("c", [])`, `.accessibilityLabel("Complete reminder")`, `.accessibilityAddTraits(.isButton)`; Skip Button analogous with `"s"` shortcut, `.tint(.orange)`. `bottomBar` also lists mic-button / dictation state.
- **Widget** (`SingleThreadWidget/NextThingWidget.swift`): provider builds `NextThingEntry(state:.reminder(ReminderDisplay))` from `store.visibleReminders.first` (:63–67). `NextThingWidgetView.actionButtons` (:126–141): two `Button(intent: CompleteReminderIntent())` / `Button(intent: SkipReminderIntent())`, both `Label(…, systemImage:)`, `.tint(.green / .orange)`, `.buttonStyle(.bordered)`, `.accessibilityLabel("Complete reminder"/"Skip reminder")`. Widget has no `tint` or keyboard shortcut — activation goes through AppIntents.
- **Watch** (`SingleThreadWatch/WatchReminderView.swift`): `reminderContent` picks `store.visibleReminders.first` (WatchReminderView.swift:69) else All-Done/No-Reminders state. `actionButtons` (HStack, :83–96): Complete `Task { await store.completeCurrentReminder() }` tinted green, Skip `store.skipCurrentReminder()` tinted orange. `reminderCard` wraps the details in a `ScrollView` with a long-press refresh + `confirmationDialog` (:137).

---

## Q3: Mutation funnel through the store + cross-surface relay

**Findings**

- **MainActor boundary:** `ReminderStore` is `@MainActor @Observable` (ReminderStore.swift:5–7) and the whole `EventKitStoring` protocol is `@MainActor`. `SingleThreadCore` does not set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (that's set only on app/watch targets), so `ReminderStore`'s explicit `@MainActor` marks the shared mutation boundary.
- **Writes funnel** through four public methods:
  - `completeCurrentReminder()` :138 → `completeReminder(identifier:)` :121.
  - `skipCurrentReminder()` :173 (interactive; sleeps then `applySkipSet`) and `skipCurrentReminderImmediately()` :198 (widget path; writes before returning, no sleep).
  - `addReminder(...) -> Bool` :148.
  - `setExcludedProjectTitles(_:)` :249 and `setSortOption(_:)` :184 also mutate state.
- **Settle delay:** `eventKitSettleDelay = 200_000_000` ns (0.2 s) — ReminderStore.swift:279 — slept with `Task.sleep(nanoseconds:)` after `save` in `completeReminder` (:130) and `addReminder` (:163), and in the interactive `skipCurrentReminder` (:177) before `applySkipSet` (so EventKit reflects the in-flight write).
- **Hooks** (all `var <name>: (…) -> Void`):
  - `applySkipSet` (:297–303) → `skipStore.save`, then `onViewSetChanged?(updated)` + `onRemindersChanged?()`.
  - `completeReminder` end (iOS branch) → `reload()` which ends with `onRemindersChanged?()`.
  - `addReminder` success → `reload()` → `onRemindersChanged?()`.
  - `reload(clearSettings:)` with `clearSkipped:true` also calls `onSkipSetChanged?([])` (ReminderStore.swift:236).
  - `setSortOption` fires `onSortOptionChanged` + `onRemindersChanged` (:188–190). `setExcludedProjectTitles` fires `onExcludedProjectsChanged` + `onRemindersChanged` (:255–256).
- **iOS wiring** (`SingleThreadApp.swift`):
  - Builds a `SkippedReminderSyncService(session: WCSession.default, skipStore:, showDateStore:…)` (:24) — the service owns the skip list for sync.
  - `service.onCompleteReminderReceived = { [weak store] id in Task { await store?.completeReminder(id) } }` (:35).
  - Store hooks → service: `onSkipSetChanged` → `service.push(ids, showUndatedReminders:…)` (39–40); `onShowUndatedRemindersChanged` → `service.push(skipStore.load(), …)` (42–43); `onExcludedProjectsChanged` → `service.pushExcludedProjectTitles` (45); `onCompleteReminder` → `service.requestCompleteReminder` (46); `onSortOptionChanged` → `service.pushSortOption` (47).
  - `store.onRemindersChanged` → `WidgetCenter.shared.reloadAllTimelines()` (51–52) — widget timelines refresh on any mutation. iOS also wires `onChange(of: showDate)` to `syncService?.pushShowDate`.
- **Widget intent path (parallel mutation path):** `ReminderIntents.swift` defines the widget's mutations as their own `AppIntent` structs:
  - `CreateReminderIntent` (:7–22): constructs a fresh `ReminderStore(loadsReminders:true)`, `setSortOption(SortOptionStore().load())`, `reload()`, then `completeCurrentReminder()`.
  - `SkipReminderIntent` (:30–49): same fresh store; `reload()`; `skipCurrentReminderImmediately()`.
  - These create a **fresh store per perform**, i.e., a second mutation path outside `SingleThreadApp`'s long-lived store. Widget timeline reload is triggered by the app's `onRemindersChanged` hook.

---

## Q4: Persistence across EventKit + App Group UserDefaults

**Findings**

- **Shared App Group container:** `AppGroup.defaults` (AppGroup.swift:13–14) returns `UserDefaults(suiteName: "group.app.alanvardy.SingleThread") ?? .standard` — **App Group-backed with fallback to `.standard`** (occurs on watchOS, unregistered simulators, previews).
- **Skipped set:** `SkippedReminderStore` (ReminderSkip.swift:111–127) `load()/save()` a `[String]` under key `"skippedReminderIdentifiers"`. `ReminderSkipLogic.resolve` ignores items not reappearing in `fetched` (ReminderSkip.swift:12–15); `remindLogic.skip` calls `resolve`'s.
- **Excluded projects:** `ExcludedProjectStore` (ExcludedProjectStore.swift:4–21) — key `"excludedPresentationTitles"`.
- **Show-date:** `ShowDatePreference` (ShowDatePreference.swift:8–24) — key `"showDate"`, **defaults to `true` when missing** (so it differs from skip/exclude which default to empty).
- **Sort:** `SortOption` is `String, Sendable` (:6) with `defaultsKey="sortOption"` (:18). `SortOptionStore` (:22) load/save.
- **Per-process store capability:**
  - **iOS app:** writes skip list (`skipStore.save` from `applySkipSet`/`reload(clearSkipped)`), excluded titles (`excludeStore`), sort (`setSortOption`→`SortOptionStore`), and pushes everything via the sync service `service.push` etc.
  - **Widget extension:** builds a **fresh `ReminderStore`** every refresh (NextThingWidget.swift:58–61), reads `AppGroup.defaults.bool(forKey:"showUndatedReminders")` (:66) and `SortOptionStore().load()`. Its skip writes go through `skipCurrentReminderImmediately()` which calls `applySkipSet` → `store.save` on `SkippedReminderStore` (AppGroup-backed). It cannot create EventKit items (watchOS-alike; but widget is macOS/iOS) — actually `contextMenu` etc. live only in iOS/macOS.
  - **Watch app:** uses `SkippedReminderSyncService` with `ShowDatePreference(defaults:.standard)` (watch passes `.standard`), while its skip store defaults to `SkippedReminderStore()` = `AppGroup.defaults` → `.standard` on watchOS.
  - **Test fakes:** inject a recording `FakeEventStore(fetchResult:)` (EventKitStoringTests.swift:9) so tests never touch a real `EKEventStore` and often inject per-test `SkippedReminderStore(defaults:.standard, key:…`).
- **Removed-reminder visibility quirk:** `visibleReminders` only filters by in-memory `skippedIDs`/`excludedProjectTitles` — it does **not** itself re-fetch. A reminder that was completed/added disappears only after a `reload()`. `ReminderSkipLogic` prunes stale skip IDs against the just-fetched identifier set during `reload()` — that's the "where a removed reminder stays visible until reload" seam.
- **showsUndatedReminders / date predicate:** `reload()` chooses `nil/nil` start/end when `showsUndatedReminders` true, else `ReminderDateFilter.overdueCutoff()` .. `endOfToday()` (ReminderStore.swift:211–214). The `isInCurrentWindow` gate (ReminderStore.swift:216) filters any undated item + dated items inside the window. This determines both what's fetched and which identifiers `reload()` prunes against.

---

## Q5: UI composition and accessibility conventions for the card + actions

**Findings**

- `ReminderCardView.swift` is the card body: `VStack` → `HStack(alignment:.firstTextBaseline)` priority `Text(marker)` with `.accessibilityLabel("\(level.displayName) priority")`, then title `Text(.title)`; optional date row `Text(due, style:.date)`; notes row formatted via `ReminderNotesFormatter` with `.lineLimit(3)`. Priority color: `.low → .green`, `.medium → .yellow`, `.high → .red` (ReminderCardView.swift:52–56).
- iOS contextual vs. macOS differ: iOS uses `.swipeActions(edge:.leading/.trailing)` + `.contextMenu` (ContentView.swift:289–307); macOS adds `.keyboardShortcut("c"/"s")` + a separate `actionButtons` HStack (ContentView.swift:192–215). Widget/watch share a horizontal `actionButtons` row.
- **Established button/gesture pattern** for adding a destructive action:
  - iOS swipe button: `Button { Task { await store.<mutation>() } } label: { Label("Label", systemImage:) }` + `.tint(...)` (ContentView.swift:289–303).
  - macOS: `.keyboardShortcut(<key>, [])` + `.accessibilityLabel(...)` + `.accessibilityAddTraits(.isButton)` (ContentView.swift:201–203).
  - Widget: `Button(intent:)` + `.tint` + `.buttonStyle(.bordered)` + `.accessibilityLabel` (NextThingWidget.swift:128–141).
  - Watch: plain `Button { … }`, `Label("Skip"/"Complete", systemImage:)`, `.tint` (WatchReminderView.swift:83–96).
- In every place a binary action (Complete/Skip), the tint is `.green` (complete) vs `.orange` (skip); system image is `checkmark.circle.fill` vs `circle.slash`. Settings gear uses `systemName:"gearshape"` (ContentView.swift:51), `.accessibilityLabel("Settings")`, `.accessibilityAddTraits(.isButton)`.
- `TextSizeModifier` applies `dynamicTypeSize` when non-`.system` (ContentView.swift:34).
- Previews for all surfaces use the `#Preview` macro with injected `EKReminder` / `ReminderDisplay` fixtures (ContentView.swift:433–488, WatchReminderView.swift:170–211, NextThingWidget.swift:180–210).

---

## Q6: Test and audit coverage

**Findings**

- **`FakeEventStore` (recording `EventKitStoring`)** in `SingleThreadTests/EventKitStoringTests.swift:9–115`:
  - Records `saved: [EKReminder]`, `lastSaveCommit`, `lastPredicate`, `lastAtHeight/Date`, `fetchCallCount`, `requestAccessCallCount`, `refreshCallCount`, `calendarFetchCallCount`; configurable `fetchResult`, `authStatus`, `saveShouldThrow`, `returnedCalendars`.
  - `save(_:)` throws when `saveShouldThrow` (EventKitStoringTests.swift:93–97).
- **Write-path suites** (`ReminderStoreWriteTests`, EventKitStoringTests.swift:121+):
  - `completeCurrentReminder…` → asserts `reminder.isCompleted`, `fake.saved.count==1`, `== reminder`, `lastSaveCommit==true`, `lastPredicate!=nil`, fetch count +1 (reload) — EventKitStoringTests.swift:127–142. Save-error variant asserts `saved.isEmpty` and no reload (:145–157).
  - `addReminder` asserts saved fields incl. `recurrenceRules?.count==1` and `lastSaveCommit` (:178–178, return true / false paths).
- **In-memory suites without a real store** (`ReminderStoreTests.swift`): all construct `ReminderStore(loadsReminders:false, reminders:…, skippedIDs:…, authStatus:…)` and assert on `visibleReminders`/`availableProjects`/`setSortOption` etc. Write methods (`completeCurrent`, `add` no-access, `skip`) run against real `EKEventStore()` but are `loadsReminders:false` and guard on absence. `makeReminder` faker factory (ReminderStoreTests.swift:350+) builds `EKReminder` fixtures.
- **`ReminderSkipTests.swift`** covers `ReminderSkipLogic.resolve`/`skipping`, `ReminderPriority`, `ReminderNotesFormatter`, `ReminderSort` pure logic — no EventKit.
- `SkippedReminderSyncServiceTests.swift` drives the service through a fake `SkipSyncSession` (activate/`updateApplicationDefinition`/`sendMessage`) and asserts payload keys, latest-wins replace semantics, and missing-key no-ops (lines 39–386).
- `SettingsViewTests.swift` asserts all preference rows present (single `@AppStorage`-backed test, no real store).
- App-side: `ContentView` swaps only a `.storage` preview-store? For previews it uses the `#Preview`/`loadsReminders` path, not EventKit. **Accessibility:** `SingleThreadUITests.swift:17–41` — `testAccessibilityAudit` launches with `--ui-testing` (skip access), waits for visible text, then `app.performAccessibilityAudit(for: [.dynamicType, .hitRegion, .sufficientElementDescription, .trait])` on iOS (default categories on macOS); contrast and textClipped are excluded as known-false-positives.
- **What is unit-testable without real EventKit:** all `ReminderStore` mutation methods can be exercised against `FakeEventStore` (save error/reload), plus `visibleReminders`, `SortOption`, intents, sync payloads, date filtering, projection logic.
- **What requires UI/XCTest coverage:** actual `Button` wiring (swipe actions, macOS shortcuts, watch refresh), accessibility labels/traits, SwiftUI `#Preview`, and any layout/composition behavior.

---

## Cross-Cutting Observations

- **One write seam, many surfaces.** Everything that mutates EventKit happens in `ReminderStore` (`complete`, `skip`, `add`) behind `EventKitStoring`; iOS, widget, and watch all ultimately reach it (widget/watch re-open a fresh store or call store methods directly). There is no second write path.
- **`visibleReminders`.first is the de-facto "current reminder".** Every consumer (iOS card, swipe, macOS buttons, widget entry, watch card) renders `store.visibleReminders.first`; completion/skip act on that same `.first`. The sort/exclude/skip filters that define "current" live entirely in `ReminderStore.visibleReminders` (ReminderStore.swift:95).
- **Complete is mutate-and-save; there is no delete.** The seam's only write is `save(reminder, commit:)`. Deleting an item requires an EventKit removal API that no layer currently exposes. The only item-removal that exists is the watchOS local-array `removeAll` in `completeOn watchOS`.
- **App Group defaults fall back to `.standard`.** Every store defaults to `AppGroup.defaults`, which falls back to `.standard` on watchOS/previews/simulators, so "shared skip list" behavior is best-effort and collapses to per-process standard UserDefaults when the group is unavailable.
- **Skipped IDs are pruned on reload.** `ReminderSkipLogic.resolve` treats the just-fetched identifier set as authoritative, so anything removed (or expired) disappears from `skippedIDs` after a `reload()` — the intended "removed reminder stays visible until reload" seam.
- **Mutation → hook → relay.** Every store mutation ends in `onRemindersChanged`/`onSkipSetChanged`/`onExcludedProjectsChanged`; `SingleThreadApp` forwards these to `SkippedReminderSyncService` => EventKit watch + `WidgetCenter.reloadAllTimelines()`. Only `showDate` is separate.
- **Recurrence is authored but not touched by any mutation path.** Only `makeReminder`/`addReminder` builds recurring reminders; complete/skip operate on whole `EKReminder` with `save`. No series splitting exists anywhere.

---

## Open Areas

- **EventKit-level delete API**: whether `EKEventStore`/`EKReminder` exposes any delete or delete-series method, and what its recurrences semantics would be, is not evident from this codebase (the seam does not surface such a method). Answering "how `recurrenceRules` behave under removal" requires the EventKit framework reference, not this repo.
- **Widget timeline lifecycle**: `reminders` provider builds a fresh store on every `getTimeline` poll; the durability of the widget store across process suspensions and its exact refresh cadence are not fully described here.
- **Accessibility audit details**: which SwiftUI elements actually reported `accessibilityLabel` for the new actions, and XCTest-level intero coverage of the swipe/contextMenu UI, is limited to `testAccessibilityAudit` and the unit-tested card previews.
- **Watch completion execution order**: whether `completeReminder` on watch relays before/after the local `removeAll` is refactor-gated (`onRemindersChanged` hook presence on watch) and is only partially covered by tests.