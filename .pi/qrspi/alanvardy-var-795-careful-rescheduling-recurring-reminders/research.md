# Research Findings — Reschedule & Recurrence Plumbing

Branch: `alanvardy-var-795-careful-rescheduling-recurring-reminders`. All paths relative to repo root. Line numbers verified against source.

## Q1: Reschedule action end-to-end (every UI surface → `ReminderStore.rescheduleReminder`)

### UI surfaces
- **iOS action menu**: `ContentView+ActionMenu.swift:18-24` `showActionMenu` gate = `ActionMenuGate.showsActionMenu(enableActionButtons:canMutate:hasVisibleReminder:)` (`SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:7-10`). Skip button tap (`ContentView+ActionMenu.swift:30-48`) captures `actionMenuReminder = viewModel.store.visibleReminders.first` (:33) → `.confirmationDialog` (:46) → Reschedule row (:50-54) sets `isShowingRescheduleSheet = true`. Sheet: `ContentView.swift:295-297` (`isShowingRescheduleSheet` @State :118) with `.presentationDetents([.height(320)])`. Body `actionMenuRescheduleSheet` (`ContentView+ActionMenu.swift:179-197`) = `RescheduleSheet(reminder: actionMenuRescheduleReminder, onReschedule: { … id = viewModel.store.visibleReminders.first?.calendarItemIdentifier … await viewModel.rescheduleReminder(identifier: id, to: components) })` (:183-188).
- **macOS action menu**: `macShowActionMenu` (`ContentView+ActionMenu.swift:89-96`); `macActionMenu` (:112-137), Reschedule row (:117-119) — no captured reminder; `actionMenuRescheduleReminder` (:171-174) = `visibleReminders.first`. macOS has **no context menu** (`ContentView.swift:433` `.contextMenu` is `#if os(iOS)` only).
- **iPhone nudge sheet** (6th-skip banner): in-card banner tap `onNudgeTap: openNudgeSheet` (`ContentView.swift:409,422`); `.sheet(isPresented: $isShowingNudgeSheet, onDismiss: { viewModel.dismissNudge() })` (:300-303). `nudgeSheetContent` (`ContentView+iOS.swift:59-89`) = `RescheduleSheet(…, onReschedule: { await viewModel.rescheduleNudgedReminder(to: components) }, nudgeMessage: "This reminder keeps coming back.")`; Delete + View-in-Reminders rows also present.
- **Watch action menu**: `canShowActionMenu` (`WatchReminderView.swift:81-88`) = `showEnableActionButtonsState.isEnabled && store.canMutate && visibleReminders.first != nil`. Skip tap (:142-147) → `.confirmationDialog` (:277-278) → Reschedule (:215-218) → `.sheet` (:280-282) → `actionMenuRescheduleSheet()` (:290-316): **hand-rolled date-only picker** (`DatePicker` with `displayedComponents: [.date]` :294-297), confirm builds `Calendar.current.dateComponents([.year, .month, .day], from: viewModel.rescheduleDate)` (:299-301) and calls `viewModel.store.rescheduleReminder(identifier: id, to: components)` **directly on the store** (:304-305) — `WatchReminderViewModel` carries only `isShowingRescheduleSheet`/`rescheduleDate` state (`WatchReminderViewModel.swift:65,68`), no relay method.

### View-model hop
- `ContentViewModel.rescheduleReminder(identifier:to:)` = plain forward (`ContentViewModel.swift:165-166`). Nudge variant `rescheduleNudgedReminder(to:)` (:238-244): guards `nudgeIdentifier` (:49), calls store, clears `nudgeIdentifier` only on success.

### `ReminderStore.rescheduleReminder(identifier:to:)` (`ReminderStore.swift:356-375`)
Signature :356. `guard canMutate` (:357; `canMutate` :176-179 = `entitlementStore.isEntitled || completionCounter.count < EntitlementStore.freemiumCap`).
- **watchOS branch** (:359-362): snapshots and fires `onRescheduleReminder` hook (decl :111), `return true`. No field mutation, no save, no reset, no reload.
- **iOS/macOS branch** (:363-375), in order:
  1. Lookup: `reminders.first(where: { $0.calendarItemIdentifier == identifier })` (:363-365); miss → `false`, nothing written.
  2. Mutation: **`reminder.dueDateComponents = due` only** (:367) — no recurrence, title, alarms, or calendar changes.
  3. Persist: `try eventStore.save(reminder, commit: true)` (:368) through `EventKitStoring` (decl `EventKitStoring.swift:29-31`; production = SDK `EKEventStore`; seam `InMemoryEventStore.save` appends to `allReminders`, `InMemoryEventStore.swift:87-89`).
  4. `resetSkipCount(for: identifier)` (:369; impl :581-590): filters the identifier out of the persisted skip-count map in `skipCountStore`.
  5. `await settle()` (:370; typealias `ReminderStoreSettle` :12; production default `try? await Task.sleep(nanoseconds: 200_000_000)` :39-41; tests inject no-op).
  6. `await reload()` (:371; impl :439-…): `refreshSourcesIfNecessary()` (:441-443, compiled out on watchOS); date-window predicate `overdueCutoff()..endOfToday()` unless `showsUndatedReminders` (:447-454); `fetchReminders(matching:)` (:457, async bridge :628); window filter + `hasHidden`; `reminders = shown` (array replaced wholesale — rescheduled item reappears with new due date or drops out of window); `availableLists` (:471-474); `reconcileSkipState`; `reconcileSkipCounts` (:607-617); prune pending completions; `onRemindersChanged?()` (:481-483) → widget timeline.
  7. `return true` (:372). `catch` (:373-375): logs, returns `false`, skips reset/settle/reload — in-memory list keeps old due date.

### Delete-then-recreate?
**No.** No path pairs `remove` with a rebuild. `eventStore.remove` is reached only from `deleteReminder` (`ReminderStore.swift:296-311`); `makeReminder` only from `addReminder` (:325-343). `rescheduleReminder` mutates the fetched instance in place and saves once. (Artifact: `InMemoryEventStore.save` appends without dedup, `InMemoryEventStore.swift:87-89`, so a unit test rescheduling a seeded reminder sees it twice on the next fetch — seam behavior, not production remove/recreate.)

### Platform differences
- iOS: two surfaces (action-menu dialog + nudge sheet); dialog captures reminder at tap time.
- macOS: one surface (bottom-bar Menu, `visibleReminders.first`); no nudge (the skip-nudge interrupt is `#if os(iOS) || os(watchOS)`, `ReminderStore.swift:383-389`); no context menu.
- watch: one surface; store branch only relays; sheet always emits `.year/.month/.day` (time always dropped).

## Q2: What save/round-trip does to `recurrenceRules`

### The protocol + adapter
- `EventKitStoring` (`EventKitStoring.swift:8`); write surface is `#if !os(watchOS)` (:26-41): `save(_:commit:)` :29, `remove(_:commit:)` :33, `makeReminder(title:notes:dueDate:recurrenceRule:)` :37-41. Read surface: `authorizationStatus` :10, `calendars(for:)` :12, `requestFullAccessToReminders` :14, `predicateForIncompleteReminders` :16-18, `fetchReminders` :22-24.
- `extension EKEventStore: EventKitStoring` (:45-66). Body only for `authorizationStatus` (:46-48) and `makeReminder` (:51-64): `EKReminder(eventStore: self)` + title/notes/dueDateComponents + `if let recurrenceRule { reminder.addRecurrenceRule(recurrenceRule) }` (:60-61) + `defaultCalendarForNewReminders()` (:63). `save`/`remove`/fetches are the SDK's own methods — no wrapper.

### Every production save site (all `ReminderStore.swift`)
| Site | Line | Operation |
|---|---|---|
| complete | :245 | `save(reminder, commit: true)` in place (`isCompleted = true` :244) |
| undo | :277 | save of the retained instance (`isCompleted = false` :276) |
| delete | :305 | `remove(reminder, commit: true)` — whole object |
| add | :339 | save of `makeReminder(...)` (:333-338) — **only construction path** |
| reschedule | :368 | save of the fetched instance (`dueDateComponents = due` :367) |

### Recurrence through each path
- **Preserved by object identity**: complete/undo/reschedule mutate and re-save the exact `EKReminder` last fetched from the store; `recurrenceRules` is never read, rewritten, or re-derived on these paths. `UndoStore.retain` stores the same reference (`UndoStore.swift:31-43`).
- **`addReminder`** (`ReminderStore.swift:325-343`) carries exactly title/notes/dueDate/recurrenceRule into `makeReminder` — recurrence is whatever the caller passes (other fields: priority/alarms/URL/completion state are omitted). Only production caller: `DictationViewModel.swift:75-79` with `parsed.recurrenceRule` from `ReminderDictationParser` (fresh `EKRecurrenceRule` built from text: `ReminderDictationParser.swift:163-175` orchestrates regex tries; constructors `matchEveryOther` :220, `matchEveryFrequency` :233, `matchSynonym` :242, `weeklyRule` :252-262; result struct :18-37).
- **Skip/defer** (`ReminderStore.swift:380-410`, `skipCurrentReminderImmediately` :421-434): never touches an `EKReminder` — only skip-ID sets persisted in `skipStore` (`applySkipSet` :610-622) and hooks. Recurrence irrelevant.
- **Dictation re-parse**: creates a new reminder via `addReminder`; never reads an existing reminder's recurrence.
- **`reload()`** (`ReminderStore.swift:439-…`): fetches full hydrated `EKReminder` objects and only filters/sorts/derives — no field-by-field copy, nothing rebuilt. Real store: recurrence survives as EventKit rehydrates it. Seam stores: same references, trivially preserved.
- **Constructed-but-never-saved** `EKReminder`s: `UITestingSeed` materialize (`UITestingSeed.swift:147-154`; seed schema `ReminderSeed` has only title/notes/priority :123-126 — **no recurrence field exists in the seed format**); `--ui-testing` seam `makeReminder(..., recurrenceRule: nil)` (`AppViewModel.swift:230-235`); canvas previews (`ContentView+Previews.swift:12-21`, `mockReminder` adds a weekly rule :19); watch `--ui-testing` seam (`WatchAppViewModel.swift:110-136`); watch previews (`WatchReminderView.swift:382-398`). None enters a save path.

## Q3: Recurrence representation, creation, formatting, display, and flow interaction

- **Representation**: EventKit's own type only — `EKRecurrenceRule` inside `EKReminder.recurrenceRules: [EKRecurrenceRule]?` (+ `hasRecurrenceRules`). No app-side recurrence type. It crosses the app boundary only via `EventKitStoring.makeReminder(... recurrenceRule: EKRecurrenceRule?)` (`EventKitStoring.swift:37-41`).
- **Read sites (complete)**: `ReminderDisplay.swift:17` `hasRecurrence = reminder.hasRecurrenceRules`; :18 `recurrenceSummary = ReminderRecurrenceFormatter.format(reminder.recurrenceRules)`; formatter reads `rules?.first` / `.interval` / `.frequency` (`ReminderRecurrenceFormatter.swift:11-31`). Grep confirms **no other production read sites** (ReminderStore, sorting, filtering, skip, gating never consult recurrence).
- **Write sites**: only the two `makeReminder` factories (`EventKitStoring.swift:61`, `InMemoryEventStore.swift:103-118`), the dictation parser (above), and the canvas preview fixture. **No code mutates or clears recurrence on an already-saved reminder** — no `recurrenceRules =`, no `removeRecurrenceRule`, no re-derivation.
- **Formatting**: `ReminderRecurrenceFormatter.format` formats only the **first** rule's frequency + interval → "Daily"/"Weekly"/"Monthly"/"Yearly" or "Every N …"; nil/empty/unrecognized → `nil` (`ReminderRecurrenceFormatter.swift:11-31`).
- **Display (3 surfaces, each gated by the `showRecurrence` preference, default true)**:
  - iOS card: `ReminderCardView.swift:107-116` (`if showRecurrence, display.hasRecurrence` → `Image(systemName: "repeat")` + summary-or-`SharedStrings.repeats`, `.accessibilityIdentifier("recurrenceLabel")` :115). Preference: `PreferenceHolder.swift:36,54-55`; `SettingsBindings.swift:125-133,173-174`; toggle `ReminderSettingsView.swift:50-62`; passed at `ContentView.swift:414`. Fallback string `SharedStrings.repeats` = "Repeats" (`LocalizedString+Shared.swift:53-55`).
  - Watch: `WatchReminderView.swift:345-349` + `ShowRecurrenceState.swift:9-31` (synced phone→watch, `SkippedReminderSyncService.swift:190` push, receive → `WatchAppViewModel.swift:263-264`).
  - Widget: `NextThingWidget.swift:212-216` (preference read :60).
- **Flow interaction with repeating reminders**: complete (`ReminderStore.swift:220-254`), undo (:271-290), skip (:380-410, :421-434), delete (:296-313), reschedule (:356-375) all operate on the same in-place object. **No next-occurrence generation, no series-vs-one-off logic anywhere.** The only series-related statement in the repo is the doc comment on `EventKitStoring.remove`: "Removes the whole repository object, so a recurring reminder's entire series is deleted (no per-occurrence span)" (`EventKitStoring.swift:31-32`).

## Q4: Where behavior branches on recurrence

- **Only three branches, all display-only**: `ReminderCardView.swift:107`, `WatchReminderView.swift:345`, `NextThingWidget.swift:212` — each renders/hides the "repeat + summary" row, gated by `showRecurrence` (a display preference; never feeds any action).
- **Action visibility**: never checks recurrence. Every action (skip/reschedule/delete/undo/complete) is gated only by `enableActionButtons`, `canMutate`, and visible-reminder presence: `ActionMenuGate.swift:7-10`, `ContentView+ActionMenu.swift:18-24`, watch `canShowActionMenu` (`WatchReminderView.swift:81-88`), iOS undo gate (`ContentView.swift:214`, adds `undoStore.hasUndoableReminder`).
- **Delete-as-series**: `EventKitStoring.remove` deletes the whole `EKReminder` (series included); no `delete(withOccurrence:)` / per-occurrence API exists anywhere (grep negative). Mirror store removes by `calendarItemIdentifier` (`InMemoryEventStore.swift:91-93`). No delete confirmation carries series/occurrence language.
- **Store guards**: `canMutate` (entitlement/freemium cap, `ReminderStore.swift:176-179`) is the only gate on every mutation; no store method consults `hasRecurrenceRules`.
- **Flows that treat repeating reminders identically to one-offs (no check)**: skip (all surfaces + widget intent), complete (all surfaces), undo, delete (all surfaces, series-wide), reschedule (all surfaces + watch relay), reload/settle/fetch.

## Q5: Test coverage of reschedule and recurrence

### Reschedule tests
- `RescheduleSheetTests.swift` (picker logic, no store): `dateOnlyReminderPicksDateWithoutTime` :15, `timedReminderPicksDateAndTime` :23, `reminderWithoutDueDateIsDateOnly` :31, `nilReminderIsDateOnly` :38, `writeBackMaskFollowsDueTime` :43.
- `EventKitStoringTests.swift`: `reschedulePersistsDueDateAndReloads` :274 (asserts new due date on the **saved** reminder and `fake.saved.last === reminder` — same object, :315), `rescheduleUnknownIdentifierIsNoop` :298, `rescheduleFailureReturnsFalse` :313; `completeReminderMarksSavedAndReloads` :143-154 (`===` :152).
- `ReminderStoreTests.swift`: `rescheduleResetsSkipCount` :674 — seeds a skip count of 6, asserts count → 0 after reschedule.
- `SingleThreadTests.swift`: `rescheduleSheetTextButtonsKeepNativeChrome` :142.
- `RescheduleSyncTests.swift` (relay; file starts `#if os(iOS) || os(watchOS)` :1, compiled into both unit-test targets): `requestRescheduleReminderSendsMessage` :12, `requestRescheduleOmitsNilComponents` :35, `receiveRescheduleReminderFiresHook` :54, `receiveMessageWithoutRescheduleKeyIsNoOp` :90.
- Watch unit: `SingleThreadWatchTests/ReminderStoreWatchTests.swift` `rescheduleFiresRelayHookAndReturnsTrue` :111, `rescheduleNoOpWhenGated` :143.
- UI: `SingleThreadWatchUITestsFlows.swift:159` `testActionMenuReschedulePresentsSheetWhenToggleSyncedOn` (drives menu → sheet → `rescheduleConfirmButton`); iOS has **no** reschedule UI test — `SkipNudgeUITests.swift:10` only documents the sheet in a comment.

### Recurrence tests
- `ReminderDictationParserTests.swift:141-316` — 19 recurrence-parse tests ("every week/day/month/year/other", weekdays, synonyms, intervals). `multipleDatesUsesFirst` :141 is the only test whose input contains the word "rescheduled" (parsed as title text; unrelated to the feature).
- `ReminderRecurrenceFormatterTests.swift:10,16` (nil/empty → nil; known rule strings).
- `ShowRecurrenceTests.swift:11` (card row follows preference + data); `ReminderDisplayTests.swift:146` (`recurrenceFlagsAndSummary`, parameterized).
- `ReminderStoreTests.swift:222` (`addReminderSucceedsAndKeepsExistingReminders`, weekly rule), :1043 (`makeReminderLeavesUnsetFieldsNil`), :1053 (`makeReminderSetsRecurrenceRule` — count/frequency/interval).
- `EventKitStoringTests.swift:206` `addReminderSavesAndReturnsTrue` asserts `saved.first?.recurrenceRules?.count == 1` after the save round-trip (:223); `FakeEventStore.makeReminder` mirrors production (:122-132).
- Watch recurrence tests are about the **showRecurrence preference**, not `EKRecurrenceRule`: `WatchSyncPipelineTests.swift:69,133,177-182,229,267`; `ShowCompletionGlowStateTests.swift`; `WatchReminderViewModelTests.swift:44,108`; `WatchReminderViewRegressionTests.swift:34` (asserts `!display.hasRecurrence` :43).

### Gaps (facts, not suggestions)
- **No test combines a repeating reminder with a reschedule.** All reschedule tests use title-only reminders; the `--seed`/`--ui-testing` seams cannot express recurrence (`UITestingSeed.swift:123-126`).
- No test verifies recurrence-rule survival across a **real** EventKit save→fetch round-trip (assertions exist only for the write path and `makeReminder`).
- `InMemoryEventStore` (`InMemoryEventStore.swift`): `save` appends the same `EKReminder` reference (:87-89) — a re-save (exactly what reschedule does to a seeded reminder) duplicates it in `allReminders`, and the next fetch returns it twice; no test asserts this. `fetchReminders` returns same references filtered by `!isCompleted` (:57-60); `remove` by identifier (:91-93); rules survive trivially because there is no load/deserialization layer. Real `EKEventStore`: true persistence, fresh objects per fetch — survival depends on EventKit, not object identity.

## Q6: WatchOS reschedule relay

Path (verified hop by hop):
1. `WatchReminderView.swift:142-147` (skip branch) → `.confirmationDialog` :277-278 → Reschedule :215-218 → `.sheet` :280-282 → `actionMenuRescheduleSheet()` :290-316; components `.year/.month/.day` only (:299-301); `store.rescheduleReminder(identifier: id, to: components)` (:304-305) with `id = visibleReminders.first?.calendarItemIdentifier` (:302).
2. `ReminderStore.swift:358-362` watchOS branch: `guard canMutate` (:357), fires `onRescheduleReminder` (decl :111), returns true. No local write/reload.
3. `WatchAppViewModel.swift:216-223` `wireStoreSyncHooks`: → `service.requestRescheduleReminder(identifier:dueDateComponents:)` (:220-221).
4. `SkippedReminderSyncService.swift:268-291`: payload = `[PayloadKey.rescheduleReminderIdentifier: identifier]` (:269; key const :348) + nested `"dueDateComponents"` `[String: Int]` with inline keys `year/month/day/hour/minute`, each included only when non-nil (:271-286); `session.sendMessage(payload, replyHandler: nil)` :287-289 — **fire-and-forget, no acknowledgment**.
5. Phone receive: `session(_:didReceiveMessage:)` :300-321; reschedule branch requires both keys (:309-310), rebuilds `DateComponents` (:311-315), fires `onRescheduleReminderReceived` (:316-317; decl :108).
6. `AppViewModel.swift:384-386`: `onRescheduleReminderReceived = { identifier, components in Task { await store?.rescheduleReminder(identifier:to:) } }` (wired in `setupSyncService` :359-386, called from init :30).
7. Phone store applies the iOS branch of Q1 (mutate `dueDateComponents` in place → save → resetSkipCount → settle → reload).

**Data on the wire**: identifier + up to five due-date component ints. **Omitted**: title, notes, priority, alarms, calendar, recurrence rules, completion state, seconds, timezone. Watch live path always sends y/m/d with hour/minute nil (date-only picker).

**Reconstruction vs mutation**: the phone **mutates the existing `EKReminder` by identifier** (`ReminderStore.swift:363-368`); no `makeReminder`/recreate anywhere in this path. Consequently a repeating reminder's `recurrenceRules` **survives the relay** (untouched on the live object). Side effects: watch-side reschedule of a timed reminder replaces its time-of-day with nil; the watch card shows the old date until its next `reload()`.

## Cross-Cutting Observations

- **Object-identity mutation is the universal pattern**: every mutation (complete, undo, reschedule) mutates and re-saves the `EKReminder` instance last fetched by `reload()`; recurrence survives every such path structurally. The only new-`EKReminder`-into-save path is `addReminder`.
- **Recurrence is display-only**: exactly three read sites (all display), three branch sites (all display rows), no action/store/sync logic keys on it. The delete-as-series doc comment (`EventKitStoring.swift:31-32`) is the only series-vs-one-off statement in the repo.
- **The watch relay is identifier-addressed**: it never ships or reconstructs reminder content, so it cannot drop recurrence — but it also cannot represent time, occurrence-scope, or any other attribute.
- **Nudge/undo state lives beside the store**: skip counts (`skipCountStore`), undo (`UndoStore`), pending completions — all keyed by identifier, all reset/cleared on reschedule (skip counts) or irrelevant (undo retains the same object).
- **Test seams define the observable surface**: `InMemoryEventStore` duplicates on re-save, seed/UI-test formats cannot express recurrence — any test combining recurrence × reschedule must build rules via `makeReminder`, not seeds.

## Open Areas

- Whether EventKit itself advances/re-derives due dates for a recurring reminder after `dueDateComponents` is rewritten on a save (behaviour of the real store is not asserted by any test) — unverified.
- Watch-card refresh timing after a relay-applied reschedule (no local reload on watchOS; propagation depends on the watch's EventKit copy) — untested.
- How the dictation parser's `weeklyRule` weekday rules interact with a later reschedule (no test) — untested.
- What happens to the series when the rescheduled due date moves its anchor relative to the rule (e.g. daily rule + new date) — no code path or test addresses this; the app never reads the rule at reschedule time.