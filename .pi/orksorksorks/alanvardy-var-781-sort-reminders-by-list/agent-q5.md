# Agent Q5 — Sort behavior testing

## 1. Unit tests (Swift Testing, `SingleThreadTests`) guarding reminder ordering

### 1a. Comparator level — `ReminderSortTests`
`SingleThreadTests/ReminderSkipTests.swift`, `struct ReminderSortTests` at `:134`:
- `sortsByPriorityThenDateThenTitle()` `:138` — high(1) before low(9) (`:144`), high-before-medium-before-low (`:146-148`), prioritized before no-priority (`:150-151`).
- `sortsWithinSamePriorityByDateThenTitle()` `:152` — same priority: earlier date first (`:156-157`), dated before undated (`:159-161`), case-insensitive alphabetical tie-break (`:163-166`).
- `priorityOptionMatchesLegacyComparator()` `:165` — pins 2-arg legacy entry == `.priority` option path (`:168-173`).
- `dueDateOptionSortsSoonestFirst()` `:176` — `.dueDate` mode ignores priority (`:179-181`), dated before undated (`:183-185`).
- `titleOptionSortsCaseInsensitively()` `:188` — `.title` mode ignores priority, case-insensitive A→Z (`:191-193`), same-title tie broken by sooner due date (`:195-199`).
- Fixtures: `makeReminder(title:priority:dateComponents:)` `:202-212` builds bare `EKReminder`s on a throwaway `EKEventStore` (construction only, never saved; `:204-205`); `titles(of:)` overloads `:214-220`; `date(_:)` `:222`.

Adjacent in same file, `ReminderPriorityTests` `:57` pins the priority→display/rank mapping consumed by the comparator: `levelMapsEveryPriority` `:66` (1–4 high, 5 medium, 6–9 low, else nil) and `markerAndRankMap` `:95` (rank 0/1/2/nil). Production: `ReminderPriority` at `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:31`, `level(for:)` `:60`, `rank(for:)` `:82`.

### 1b. Comparator production code under test
`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`:
- 2-arg legacy comparator `:9-11` (delegates to `.priority`).
- Option-aware comparator `:14-31`: `.priority` = rank → due date → title (`:19-25`), `.dueDate` = date → title (`:27-30`), `.title` = title → date (`:32-41`).
- `comparePriorities` `:34-45`, `compareDueDates` `:47-59`, `titleComparison` `:61-63`.

### 1c. Sort option type/store level
`SingleThreadTests/SortOptionTests.swift`:
- `SortOptionTests` `:6` — raw values `"priority"/"dueDate"/"title"` `:9-13`; `allCases` order `[.priority, .dueDate, .title]` `:16-19`; `defaultsKey == "sortOption"` `:20-23`; presentation titles `:25-30`; SF symbols `:32-36`.
- `SortOptionStoreTests` `:39` — defaults to `.priority` when key missing (`:42-45`) or invalid (`:48-55`); save/load round-trip (`:57-63`).

Production: `SortOption` cases `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift:4-10`, `defaultsKey` `:18`, `SortOptionStore` `:22-49`.

### 1d. Store level — `ReminderStore.visibleReminders`
`SingleThreadTests/ReminderStoreTests.swift` (`@MainActor @Suite(.serialized)` `:17-18`):
- `visibleRemindersFiltersSkippedAndEmpty()` `:20-39`.
- `visibleRemindersSortsByPriorityThenDate()` `:51-75` — `visibleReminders.map(\.title) == ["high","low"]` (`:60`) and `["dated","undated"]` (`:73`).
- `visibleRemindersFiltersExcludedListTitles()` `:77-108` — exclusion by `calendar?.title`, nil-calendar never excluded (`:96-101`).
- `setSortOptionReordersAndNotifies()` `:168-217` — default `.priority` yields `["HighLater","LowSooner"]` (`:184-185`); `.dueDate` reorders to `["LowSooner","HighLater"]` (`:186-188`); hooks `onSortOptionChanged`/`onRemindersChanged` fire (`:197-203`); three identical `setSortOption(.title)` calls notify once (`:205-216`).
- Fixtures `makeReminder(title:priority:dateComponents:)` `:1098-1105` and `makeReminder(title:calendarTitle:)` `:1107-1115` over `sharedTestEventStore` `:1096`.

Production under test: `visibleReminders` `ReminderStore.swift:147-152`; `sortOption` stored property default `.priority` (`:77`); `setSortOption` `:407-415`.

### 1e. Related but not ordering-guarding
- `SingleThreadTests/EventKitStoringTests.swift` `reloadWithShowsUndatedUsesNilPredicateAndFiltersWindow()` `:454-467` asserts raw fetch `store.reminders` order (`["Undated","Now"]`, `:465`) — fetch/window predicate, not `ReminderSort`.
- `SingleThreadWatchTests/WatchSyncPipelineTests.swift` guards sort **transport**: push context includes `sortOption` (`:47-65`, `:65`), receiving `"dueDate"` persists + fires callback (`:79-128`), absent key no-op/retained (`:143-170`), exclusion filter via `visibleReminders` as unordered `Set` (`:218`, `:224`).
- No `ContentViewModelTests` cover sort; no unit test exercises the sort picker beyond label presence (`SingleThreadTests/SettingsViewTests.swift:175` `filterSortSettingsViewContainsExpectedRows` at `:166-...`).

## 2. UI tests (XCTest, `SingleThreadUITests`) asserting reminder order

The iOS UI renders a single reminder card at a time — always `visibleReminders.first` (`SingleThread/ContentView.swift:413`, `ContentView+ActionMenu.swift:22,33,66,168,181`, `ContentView+iOS.swift:87`). **No multi-card list UI**, so UI-level order assertions are implicit: which card is shown first, which after skip/complete.

- `SingleThreadUITests/SingleThreadUITestsFlows.swift` `testSkipAdvancesToNextReminder()` `:54-72` — the **only direct UI assertion of sort order**: seeds `[{"title":"First","priority":1},{"title":"Second","priority":9}]`; asserts "First" appears first ("Highest-priority reminder should be shown first", `:60`), swipes left to Skip (`:61-65`), asserts "Second" appears after skipping (`:69-72`).
- `testPriorityMarkerRendersForMidRangeValue()` `:74-85` — priority 3 renders "High priority" marker (display).
- `testSkipWithCrossDeviceCompletionShowsOnlyRemainingReminder()` `:110-147` — relies on priority ordering with distinct rank buckets 1/5/9 (comment `:114-116`): completes "CrossDevice" (first shown), skips "ToSkip" (next shown), asserts only "Remaining" remains (`:120-146`).
- `testSettingsOpensAndShowsControls()` `:224-259` — navigates to Filtering & Sorting and asserts only that text "Sort By" exists (`:244`); never changes the sort.
- Other UI tests use single-reminder seeds and assert only empty-state advance after skip/complete/delete: `testListShowsSeededReminder` `:23-31`, `testCompleteViaSwipeRemovesReminder` `:149-165`, `testDeleteViaContextMenuRemovesReminder` `:167-182`, `ActionButtonsUITests.swift` `testActionButtonsRenderAndSkipAdvancesCard` `:20-51` (via `--ui-testing`, not seed), `ActionMenuUITests.swift` `:22,42,66,97`.
- **No UI test** changes the Sort By picker, and none asserts `.dueDate` or `.title` mode ordering end-to-end; no `sortByPicker` reference in test code (`grep "sortByPicker"` → only `SingleThread/FilterSortSettingsView.swift:27` has the "Sort By" label; the picker itself has an accessibility id, untapped by tests).

Helper seam: `SingleThreadUITestCase.launchSeeded(_:extra:)` `SingleThreadUITests/SingleThreadUITestCase.swift:29-31`, `launchApp(arguments:)` `:16-26`.

## 3. What the `--seed` JSON UI-testing seam can stage

Defined in `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`; schema doc `:4-41`; consumed at `SingleThread/AppViewModel.swift` `makeStore(arguments:)` `:244-290` → `seededStore(_:)` `:292-349`.

**Per-reminder fields** (`struct ReminderSeed` `:123-126`):
- `title` (required String, `:124`)
- `notes` (optional String, `:125`)
- `priority` (optional Int, written only when present, `materialize()` `:150-152`)

**Top-level fields** (`SeedPayload` decode `:112-118`, keys pinned in `CodingKeys` `:175-183`):
- `reminders` — required array.
- `calendars` — optional `[String]` (default `[]`, `:112`); materialized as `EKCalendar(for: .reminder)` per title (`:139-143`).
- `excludedLists` — optional `[String]` (default `[]`, `:113`); becomes `excludedListTitles` (`:48`, `:164`), applied via `store.setExcludedListTitles` (`AppViewModel.swift:343-345`).
- `completionCount` — optional Int (default 0, `:114`), deliberately unclamped (`:27-32`, `:57-64`); written verbatim to `AppGroup.defaults` (`AppViewModel.swift:315-321`).
- `skipCounts` — optional title-keyed `[String:Int]` (default `[:]`, `:115`); resolved to identifier-keyed at materialization (`:155-163`); written in `seededStore` (`AppViewModel.swift:322-327`).
- `isEntitled` — optional Bool (default false, `:116`) → `EntitlementStore(testingWithEntitled:)` (`AppViewModel.swift:330-335`).
- `hasHidden` — optional Bool (default false, `:117`); only meaningful with empty `reminders` (`:23-25`); plumbed as `ReminderStore(hasHidden:)` + `loadsReminders: !emptyWithHidden` (`AppViewModel.swift:336-341`).
- `entitlementUnresolved` — optional Bool (default false, `:118`) → `EntitlementStore(testingWithEntitlementUnresolved:)` (`AppViewModel.swift:330-335`).

The seam always force-enables `enableActionButtons` in `AppGroup.defaults` (`AppViewModel.swift:328-329`) and calls `UITestingSeed.resetPersistedState()` (`:293`, `UITestingSeed.swift:62-67`), which clears 24 persisted keys from both `AppGroup.defaults` and `.standard` (`persistedKeys` `:73-98`, including `sortOption` at `:83`).

## 4. What the `--seed` seam is **unable** to stage

1. **No due dates** — `ReminderSeed` has no `dueDateComponents` field (`:124-126`); `materialize()` never sets `dueDateComponents` (`:147-154`). Every seeded reminder is undated → `.dueDate`-mode ordering, "dated before undated", and due-date tie-breaks **cannot be exercised through the UI seam**.
2. **No sort option** — payload has no `sortOption` key (`CodingKeys` `:179-183`), and `seededStore` never calls `setSortOption`/assigns `store.sortOption` (`AppViewModel.swift:292-349`). Worse, `resetPersistedState()` *removes* the persisted `sortOption` (`:83`), so every seeded launch starts at the in-memory default `.priority` (`ReminderStore.swift:77`). Non-default sort modes are unit-testable only.
3. **No completed flag** — no `isCompleted`/completion-date field; documented at `SingleThreadUITests/SingleThreadUITestsFlows.swift:103-105` ("The `--seed` schema has no `completed` flag"), which is why the cross-device completion UI test simulates completion via the real Complete swipe.
4. **No per-reminder calendar/list** — `calendars` creates list titles, but every reminder is assigned to the **first** calendar only (`defaultCalendar = createdCalendars.first` `:145`; `reminder.calendar = defaultCalendar` `:153`). A seed cannot put different reminders on different lists.
5. **No recurrence, alarms, URL, or due-date string** — none exist in `ReminderSeed`.
6. **No `showUndatedReminders`/`showDate` prefs** — not in schema; `resetPersistedState` clears `showUndatedReminders` and `showDate` (`:81-82`).
7. `priority` accepts any Int, but ordering semantics follow `ReminderPriority.rank` (`ReminderSkip.swift:82`): 1–4 high, 5 medium, 6–9 low, everything else (incl. 0) no-priority — a seed can only land reminders in those four buckets.