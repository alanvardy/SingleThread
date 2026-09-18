# Implementation Plan

## Overview

Add a "View sorted and filtered list" row to the Filtering & Sorting settings
subscreen that pushes a read-only, scrollable list of every reminder currently
visible under the user's sort/filter settings. Nothing new is computed: the row
renders `ReminderStore.visibleReminders`, which already applies skipped-ID and
excluded-list filtering plus `ReminderSort` / AI ordering. The work is view-layer
plumbing: thread the live store into the settings tree, add the push destination,
render `ReminderDisplay` rows, and add the four new localized strings.

Two phases, one commit each:

1. **Walking skeleton** — the row exists, pushes, and shows the ordered filtered
   set (titles), with the store threaded end-to-end and unit tests proving the
   ordering/filtering reaches the view.
2. **Row fidelity + empty state** — rows carry list/due-date/priority context and
   an empty visible set explains itself.

## Decisions already signed off (do not re-litigate)

- **Representation**: pushed read-only scrollable `Form` list of compact rows
  (title + caption), reusing the Excluded Lists push pattern — NOT
  `ReminderCardView` rows, NOT tap-through progression.
- **Read-only**: no complete/skip/delete actions on rows; no `ContentViewModel`
  mutation wiring.

## What recon changed from `medium.md`

- `medium.md` assumed a second **sheet** wired through `ContentView.swift`
  ("settings sheet → list sheet"). Recon shows all settings subscreens are
  **pushed** inside `SettingsView`'s `NavigationStack` (`ExcludedListsView` is a
  `NavigationLink` destination on `FilterSortSettingsView`'s `Form`). So the new
  surface is a push destination and **`SingleThread/ContentView.swift` is not
  touched at all**. The only `ContentView`-side change is one argument in
  `SingleThread/ContentView+Settings.swift`.
- `medium.md` listed `ContentViewModel` as "possibly" involved. It is not: the
  store is reached via `viewModel.store` at the `ContentView+Settings` call site
  and passed down as a plain `ReminderStore` value (same style as the existing
  `availableLists: [String]` threading).
- `SingleThread/Resources/Localizable.xcstrings` is validated by
  `SingleThreadTests/LocalizationTests.swift`: **every key must carry
  `en, zh-Hans, es, ja, de, fr`** with non-empty values, and
  `nonEnglishValuesDifferFromEnglish` fails any non-English value
  byte-identical to its English source. All four new keys therefore ship 6
  genuinely distinct translations (given below, ready to paste).
- No `Makefile` / `scripts/test.sh` change is needed: `make test` already runs
  `-only-testing:SingleThreadTests` target-wide, so a new test file in that
  target is picked up automatically.

## Non-goals (explicitly out of scope)

- Do **not** thread `showDate` / `showList` / `showRecurrence` / `showAlarms`
  display preferences into the list rows — it is a fixed compact preview row.
- Do **not** add row actions, swipe actions, or context menus.
- Do **not** change `ReminderStore`, `ReminderSort`, `SortOption`, or any
  `visibleReminders` logic; the data is already sorted/filtered correctly.
- Do **not** touch `ContentView.swift`, the main card, or the widget/watch.
- Do **not** refactor `SettingsView`'s existing `availableLists` threading or
  introduce an environment key for the store.

---

## Phase 1: Walking skeleton — the row pushes the ordered, filtered set

**Outcome**: from the Filtering & Sorting screen, tapping the new row pushes a
list showing every visible reminder title in the current sort order, with
skipped and excluded-list reminders absent. Unit tests prove the order and the
filtering reach the view, and all six localizations exist.

### Changes

#### 1. New list surface

**File**: `SingleThread/FilteredRemindersListView.swift`
**Action**: create

```swift
import SingleThreadCore
import SwiftUI

// MARK: - FilteredRemindersListView

/// Read-only list of every reminder currently visible under the Filtering &
/// Sorting preferences, in the order the store sorted them. Pushed from the
/// Filtering & Sorting sub-menu so the effect of a sort/filter choice is
/// visible at a glance — the main surface shows one card at a time.
struct FilteredRemindersListView: View {
    // MARK: Internal

    let displays: [ReminderDisplay]

    var body: some View {
        Form {
            ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                Text(display.title)
            }
        }
        .localizedNavigationTitle("Sorted & Filtered")
        .settingsSubscreenLayout()
    }
}

// MARK: - Previews

#Preview("Rows") {
    NavigationStack {
        FilteredRemindersListView(displays: [
            ReminderDisplay(title: "Call the dentist", listName: "Personal"),
            ReminderDisplay(title: "Ship the release", priorityMarker: "!!"),
            ReminderDisplay(title: "Book flights")
        ])
    }
}
```

Notes: `ReminderDisplay` is `Equatable` but not `Identifiable`, hence the
`enumerated()` + `id: \.offset` (reminder titles are not unique). New `.swift`
files need no pbxproj edit (synchronized file groups).

#### 2. Store access + the new row

**File**: `SingleThread/FilterSortSettingsView.swift`
**Action**: modify

Add the store as an input and expose the display rows (internal, so tests can
assert ordering without pushing the destination):

```swift
    @Binding var excludedLists: Set<String>

    let store: ReminderStore

    /// The current visible set as display rows — sorted and filtered by the
    /// store exactly as the main reminder card sees it. Internal so tests can
    /// assert the order without rendering the pushed destination.
    var listDisplays: [ReminderDisplay] {
        store.visibleReminders.map { reminder in ReminderDisplay(reminder: reminder) }
    }
```

Also update the struct's doc comment: it still "takes only the bindings it
needs"; the store is read-only and exists solely for the list preview.

Append a new `Section` after the existing Excluded Lists section (before the
`Form` closes):

```swift
            Section {
                NavigationLink {
                    FilteredRemindersListView(displays: listDisplays)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text("View sorted and filtered list")
                            SettingsCaption(text: "Preview how your reminders are ordered right now.")
                        }
                    } icon: {
                        Image(systemName: "list.number")
                    }
                }
                .accessibilityIdentifier("filterSortShowListRow")
            }
```

Update the `#Preview("Default")` block in the same file with a store argument
(needed in every phase-1 phase: previews must compile):

```swift
            excludedLists: .constant([]),
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false))
```

`InMemoryEventStore` avoids constructing a real `EKEventStore` (no TCC prompt);
`SingleThreadCore` is already imported in both files.

#### 3. Thread the store through `SettingsView`

**File**: `SingleThread/SettingsView.swift`
**Action**: modify

```swift
    init(
        bindings: SettingsBindings,
        backgroundImage: BackgroundImageStore,
        store: ReminderStore,
        availableLists: [String],
        excludedLists: Binding<Set<String>>,
        entitlementStore: EntitlementStore = EntitlementStore(),
        viewModel: SettingsViewModel = SettingsViewModel()) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.store = store
        self.backgroundImage = backgroundImage
        self.availableLists = availableLists
        self.entitlementStore = entitlementStore
        _excludedLists = excludedLists
    }
```

Add `private let store: ReminderStore` alongside the other stored properties
(near `private let availableLists: [String]`), and pass it into the existing
FilterSortSettingsView construction:

```swift
                        FilterSortSettingsView(
                            sortOption: $bindings.sortOption,
                            aiSortRules: $bindings.aiSortRules,
                            showUndatedReminders: $bindings.showUndatedReminders,
                            isAIRankingAvailable: bindings.isAIRankingAvailable,
                            availableLists: availableLists,
                            excludedLists: $excludedLists,
                            store: store)
```

Both `#Preview` blocks in this file need `store: ReminderStore(eventStore:
InMemoryEventStore(), loadsReminders: false),` inserted after `backgroundImage:`.

#### 4. Supply the live store at the sheet call site

**File**: `SingleThread/ContentView+Settings.swift`
**Action**: modify

```swift
        let withAppearance = SettingsView(
            bindings: bag,
            backgroundImage: viewModel.backgroundImage,
            store: viewModel.store,
            availableLists: viewModel.store.availableLists,
```

No other change: no `ContentView.swift` edit, no sheet wiring.

#### 5. New localized strings (three keys, six languages each)

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Insert each key at its alphabetically correct position (matching Xcode's
ordering and the neighbours' `extractionState`/shape), inside the top-level
`"strings"` object:

```json
    "Sorted & Filtered": {
      "extractionState": "manual",
      "localizations": {
        "en": { "stringUnit": { "state": "translated", "value": "Sorted & Filtered" } },
        "zh-Hans": { "stringUnit": { "state": "translated", "value": "排序与筛选" } },
        "es": { "stringUnit": { "state": "translated", "value": "Ordenados y filtrados" } },
        "ja": { "stringUnit": { "state": "translated", "value": "並べ替えと絞り込み" } },
        "de": { "stringUnit": { "state": "translated", "value": "Sortiert & gefiltert" } },
        "fr": { "stringUnit": { "state": "translated", "value": "Triés et filtrés" } }
      }
    },
```

The other two keys, same structure and format (values are final — every
non-English value differs from English, as `LocalizationTests` requires):

| Key | zh-Hans | es | ja | de | fr | en |
| --- | --- | --- | --- | --- | --- | --- |
| `View sorted and filtered list` | 查看已排序和筛选的列表 | Ver la lista ordenada y filtrada | 並べ替えと絞り込みを適用したリストを表示 | Sortierte und gefilterte Liste anzeigen | Afficher la liste triée et filtrée | View sorted and filtered list |
| `Preview how your reminders are ordered right now.` | 预览提醒当前的排列顺序。 | Previsualiza el orden actual de tus recordatorios. | 現在の並び順をプレビューします。 | Zeigt eine Vorschau der aktuellen Reihenfolge deiner Erinnerungen. | Aperçu de l'ordre actuel de vos rappels. | Preview how your reminders are ordered right now. |

#### 6. Shared empty-store test helper

**File**: `SingleThreadTests/TestFixtures.swift`
**Action**: modify

```swift
/// A `ReminderStore` that never touches EventKit, for view-construction tests
/// that only need the view to build.
@MainActor
func makeEmptyReminderStore() -> ReminderStore {
    ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)
}
```

#### 7. Tests: the new view, the wiring, and the existing fixtures

**File**: `SingleThreadTests/FilteredRemindersListViewTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SingleThreadCore
import SwiftUI
import Testing

// MARK: - Filtered Reminders List View Tests

@MainActor
struct FilteredRemindersListViewTests {
    @Test
    func filteredRemindersListViewRendersEveryDisplay() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "first", listName: "Work"),
            ReminderDisplay(title: "second", priorityMarker: "!!"),
            ReminderDisplay(title: "third", dueDate: Date(timeIntervalSince1970: 0))
        ])
        let bodyDescription = String(describing: view.body)

        for title in ["first", "second", "third"] {
            #expect(bodyDescription.contains(title))
        }
    }

    @Test
    func filteredRemindersListViewRendersOnlyWhatItIsGiven() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "kept")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("kept"))
        #expect(!bodyDescription.contains("skipped"), "the view renders the display list it is handed, nothing else")
    }
}
```

**File**: `SingleThreadTests/FilterSortSettingsViewTests.swift`
**Action**: modify

- Add `store: makeEmptyReminderStore()` to all six existing
  `FilterSortSettingsView(...)` constructions.
- Add `"View sorted and filtered list"` to `expectedLabels` and
  `"Preview how your reminders are ordered right now."` to `expectedCaptions`
  in `filterSortSettingsViewContainsExpectedRows`.
- Add the ordering/filtering wiring test (this is the test that proves the
  feature: the sorted+filtered set reaches the view):

```swift
    /// The list rows are the store's sorted and filtered visible set: skipped
    /// IDs and excluded-list reminders are absent, and priority order holds.
    @Test
    func filterSortSettingsViewListDisplaysMatchVisibleReminders() {
        let high = makeReminder(title: "high", priority: 1)
        let low = makeReminder(title: "low", priority: 9)
        let skipped = makeReminder(title: "skipped", priority: 1)
        let excluded = makeReminder(title: "excluded", calendarTitle: "Work")
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [low, high, skipped, excluded],
            skippedIDs: [skipped.calendarItemIdentifier],
            authorizationStatus: .fullAccess,
            excludedListTitles: ["Work"])
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: ["Work"],
            excludedLists: .constant(["Work"]),
            store: store)

        #expect(view.listDisplays.map(\.title) == ["high", "low"])
    }

    /// Sad path: an empty visible set maps to an empty row list rather than a
    /// stale or crashy surface.
    @Test
    func filterSortSettingsViewListDisplaysEmptyWhenNothingVisible() {
        let only = makeReminder(title: "gone", priority: 1)
        let store = ReminderStore(
            eventStore: InMemoryEventStore(),
            loadsReminders: false,
            reminders: [only],
            skippedIDs: [only.calendarItemIdentifier],
            authorizationStatus: .fullAccess)
        let view = FilterSortSettingsView(
            sortOption: .constant(.priority),
            aiSortRules: .constant(""),
            showUndatedReminders: .constant(false),
            isAIRankingAvailable: false,
            availableLists: [],
            excludedLists: .constant([]),
            store: store)

        #expect(view.listDisplays.isEmpty)
    }
```

The priority fixtures and expected order mirror the proven
`ReminderStoreTests.visibleRemindersSortsByPriorityAscending`, so the
expectation is not guessed.

**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Add `store: makeEmptyReminderStore(),` to the `SettingsView(...)` construction in
`settingsViewContainsNavigationLinkLabels` (line ~53). No assertion changes: the
new row lives on the Filtering & Sorting sub-view, not the root settings list.

### Verification

#### Automated

- [x] `make build` passes (uses this worktree's `.simulator_id`; pass `SIM='platform=iOS Simulator,id=<udid>'` if it is stale)
- [x] `scripts/test-one.sh SingleThreadTests/FilteredRemindersListViewTests` passes and reports a nonzero case count
- [x] `scripts/test-one.sh SingleThreadTests/FilterSortSettingsViewTests` passes and reports a nonzero case count
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` passes and reports a nonzero case count
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (proves all 6 languages on the 3 new keys and no English-identity values)
- [x] `make format` then `make lint` both pass (no staged `swiftformat` diff, `swiftlint --strict` clean)

#### Manual

- [ ] In Xcode, run the iOS app on `iPhone 17`; tap the gear (`settingsButton`) → Filtering & Sorting → **View sorted and filtered list**. The pushed screen is titled "Sorted & Filtered" and lists every reminder that the main card would cycle through, in the current sort order.
- [ ] Set Sort By to a different option, go back, re-enter the list: the order matches the new setting.
- [ ] Toggle "Show undated reminders" off, re-enter: undated reminders are absent from the list.
- [ ] Xcode preview of `FilteredRemindersListView` renders the three sample rows.

---

## Phase 2: Row context and empty state

**Outcome**: each row explains *why* it sits where it does (list, due date,
priority marker), and an empty visible set says so instead of showing a blank
form.

### Changes

#### 1. Rows carry their reminder context

**File**: `SingleThread/FilteredRemindersListView.swift`
**Action**: modify

Replace the body's bare `Text(display.title)` with a row builder and caption
composition:

```swift
    var body: some View {
        Form {
            if displays.isEmpty {
                Text("No reminders match the current filters.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("filteredRemindersEmptyState")
            } else {
                ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                    row(for: display)
                }
            }
        }
        .localizedNavigationTitle("Sorted & Filtered")
        .settingsSubscreenLayout()
    }

    // MARK: Private

    /// `ReminderDisplay`'s non-title fields as one caption line, skipping the
    /// fields this reminder does not have. Plain caption styling rather than
    /// `SettingsCaption`, because the string is composed at runtime and
    /// `SettingsCaption` takes a `LocalizedStringKey`.
    private func caption(for display: ReminderDisplay) -> String {
        var parts: [String] = []
        if let listName = display.listName, !listName.isEmpty {
            parts.append(listName)
        }
        if let dueDate = display.dueDate {
            parts.append(dueDate.formatted(date: .abbreviated, time: .omitted))
        }
        if !display.priorityMarker.isEmpty {
            parts.append(display.priorityMarker)
        }
        return parts.joined(separator: " · ")
    }

    private func row(for display: ReminderDisplay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(display.title)
            let caption = caption(for: display)
            if !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("filteredRemindersRow")
    }
```

Update the `#Preview("Rows")` sample to include one row exercising all three
caption parts (it already has list-only, priority-only, and bare rows).

#### 2. Empty-state string (fourth key, six languages)

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Add the key at its alphabetically correct position, same shape as Phase 1:

| Key | en | zh-Hans | es | ja | de | fr |
| --- | --- | --- | --- | --- | --- | --- |
| `No reminders match the current filters.` | No reminders match the current filters. | 没有提醒符合当前的筛选条件。 | Ningún recordatorio coincide con los filtros actuales. | 現在の絞り込み条件に一致するリマインダーはありません。 | Keine Erinnerung entspricht den aktuellen Filtern. | Aucun rappel ne correspond aux filtres actuels. |

#### 3. Tests: empty state and caption composition

**File**: `SingleThreadTests/FilteredRemindersListViewTests.swift`
**Action**: modify

```swift
    @Test
    func filteredRemindersListViewExplainsAnEmptySet() {
        let view = FilteredRemindersListView(displays: [])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("No reminders match the current filters."))
    }

    @Test
    func filteredRemindersListViewCaptionCarriesListAndPriority() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "ship it", listName: "Work", priorityMarker: "!!")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("Work"))
        #expect(bodyDescription.contains("!!"))
    }

    @Test
    func filteredRemindersListViewOmitsAbsentCaptionParts() {
        let view = FilteredRemindersListView(displays: [
            ReminderDisplay(title: "bare")
        ])
        let bodyDescription = String(describing: view.body)

        #expect(bodyDescription.contains("bare"))
        #expect(!bodyDescription.contains(" · "), "a reminder with no list/date/priority gets no caption line")
    }
```

Do not assert on the formatted due-date string in tests — it is locale-dependent.
Asserting the list name and priority marker covers caption composition.

### Verification

#### Automated

- [x] `make build` passes
- [x] `scripts/test-one.sh SingleThreadTests/FilteredRemindersListViewTests` passes and reports a nonzero case count
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (fourth key present in all 6 languages)
- [x] `make format` then `make lint` both pass

#### Manual

- [ ] In Xcode, run the iOS app; open the list with a reminder that has a list and a due date: the row shows title plus a "List · date" caption line.
- [ ] Skip every visible reminder (or exclude the only list), re-enter the list: it shows "No reminders match the current filters."
- [ ] Xcode preview of `FilteredRemindersListView` renders list-only, priority-only, and bare rows without layout artefacts.
- [ ] `#Preview("Default")` of `FilterSortSettingsView` still renders the Excluded Lists row and the new row.

---

## Commit sequence

- Phase 1 → `feat(VAR-1049): push sorted and filtered reminder list from settings`
- Phase 2 → `feat(VAR-1049): add reminder context rows and empty state to the list preview`

Run `make format` + `make lint` before each commit. The full CI gate
(`./scripts/test.sh`) is NOT run per phase — it runs once after all phases, via
the `run-gate` skill, per the repo's gate-staging policy.

## Notes, risks, and non-obvious calls

- **The push destination is a snapshot**: `FilteredRemindersListView(displays:
  listDisplays)` is evaluated on push, so it reflects the settings as of the
  moment the user tapped the row. Because the settings controls are not
  reachable while the destination is on screen, this satisfies "current
  Filtering & Sorting settings" and avoids a second observation path.
  Re-entering the list re-evaluates.
- **Reactivity that does matter** is preserved: `listDisplays` reads
  `store.visibleReminders`, so `FilterSortSettingsView` observes the store and
  re-renders when settings change.
- `SettingsCaption` takes a `LocalizedStringKey`; the composed row caption
  (`"Work · 1 Jan 2024 · !!"`) must use plain `Text` with caption styling — a
  runtime `String` will not compile there.
- `ReminderStore`'s init defaults construct `SkippedReminderStore` /
  `ExcludedListStore` (App-Group reads only). Production and tests already do
  this, so no store-injection change is needed.
- Force-unwrapping stays out of app code; nothing in this plan needs it.
- If `make build` is blocked by simulator contention (`Busy` /
  `RequestDenied`), do not re-run blindly — follow the `simulator-pairing`
  skill; after two UI-stage contention failures, stop and let CI be
  authoritative.