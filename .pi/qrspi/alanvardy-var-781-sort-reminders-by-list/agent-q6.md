# Agent Q6 — Settings UI structure for SortOption

## 1. Model and persistence layer (`SingleThreadCore`)

**`SortOption` enum** — `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift:4-18`
- `public enum SortOption: String, CaseIterable, Sendable`, cases `priority`, `dueDate`, `title` (lines 6-9). Core stays SwiftUI-free; doc comment at `SortOption.swift:3-4` states presentation lives in the app target.
- `public static let defaultsKey = "sortOption"` (`:16-17`) — single shared key constant consumed by `SortOptionStore` and `ContentView`'s `@AppStorage`.

**`SortOptionStore`** — `SortOption.swift:21-47`
- `init(defaults: UserDefaults = AppGroup.defaults, key: String = SortOption.defaultsKey)` (`:25-28`), `load()` falls back to `.priority` on missing/unrecognized raw value (`:34-38`), `save(_:)` (`:40-42`).

**`ReminderSort` comparator** — `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift` — `areInIncreasingOrder(_:_:using:)` switches per option: `.priority` = priority rank → due date → title, `.dueDate` = due date (dated first) → title, `.title` = case-insensitive title → due date tie-break. Legacy 2-arg entry point delegates to `.priority`. (Exact line numbers read directly from the file — see research.md; agents cited slightly different splits for the tier helpers, resolved by direct read.)

## 2. `FilterSortSettingsView` (the settings screen)

`SingleThread/FilterSortSettingsView.swift:9-62`
- Declares exactly the bindings it needs, not the whole bag: `@Binding var sortOption: SortOption` (`:10`), `@Binding var showUndatedReminders: Bool` (`:12`), `let availableLists: [String]` (`:14`), `@Binding var excludedLists: Set<String>` (`:16`). Doc comment `:6-8`: deliberate so it "cannot accidentally mutate unrelated preferences."
- Body is a `Form` (`:19-57`):
  - **Sort picker** at `:20-31`: `Picker(selection: $sortOption)` → `ForEach(SortOption.allCases, id: \.self)` with `Label(option.title, systemImage: option.systemImage).tag(option)` (`:21-26`); picker label is an un-styled `VStack` with `Text("Sort By")` + `SettingsCaption(text: "Choose the order reminders appear in.")` (`:27-29`). No `.pickerStyle`, no `.accessibilityIdentifier`, no `.onChange` on this view.
  - Show-undated toggle (`:31-40`), and a `Section` with nested `NavigationLink → ExcludedListsView` (`:41-56`).
  - `.navigationTitle("Filtering & Sorting")` (`:58`) and `.settingsSubscreenLayout()` (`:59`).

**`SortOption` presentation helpers** — `SingleThread/SortOption+Presentation.swift:10-25`
- `extension SortOption`: `var title` (`:11-16`) via `String(localized:table:bundle:)` → "Priority" / "Due Date" / "Title"; `var systemImage` (`:18-24`) → `"exclamationmark.3"` / `"calendar"` / `"textformat.abc"`. Mirrors the `AppearanceMode`/`TextSize` pattern.

**Supporting view helpers**
- `SettingsCaption` — `SingleThread/SettingsCaption.swift:9-17` (`.font(.caption)` + `.foregroundStyle(.secondary)`); `SettingsLinkLabel` `:21-37`.
- `settingsSubscreenLayout()` — `SingleThread/SettingsSubscreenLayout.swift:20-31`: macOS-only top-align frame modifier, no-op on iOS (`:25-29`).

## 3. `SettingsView` wiring (root settings list → FilterSort)

`SingleThread/SettingsView.swift`
- Root is `NavigationStack { List }` (`:24-128`). FilterSort row is a `NavigationLink` at `:92-102` passing `sortOption: $bindings.sortOption`, `showUndatedReminders: $bindings.showUndatedReminders`, `availableLists:`, `excludedLists: $excludedLists` (`:93-98`), labeled `SettingsLinkLabel(title: "Filtering & Sorting", systemImage: "line.3.horizontal.decrease", ...)` and tagged `.accessibilityIdentifier("settingsFilterSortRow")` (`:101`).
- `SettingsView` owns the bag and the store-backed excluded lists separately: `@Binding private var excludedLists: Set<String>` (`:176`), `@Bindable private var bindings: SettingsBindings` (`:178`). Doc `:9-13`: `excludedLists` is the one store-backed value passed as a separate `Binding<Set<String>>`.

## 4. `SettingsBindings` bag (in-memory snapshot, not write-through)

`SingleThread/SettingsBindings.swift`
- `@MainActor @Observable final class SettingsBindings` (`:16-18`). Doc `:4-15`: single bag of all `@AppStorage`-backed preference values, in-memory snapshot **not** write-through, `excludedLists` deliberately absent.
- `sortOption: SortOption = .priority` init default (`:35`), assigned (`:54`), stored var (`:77`).

## 5. Value flow: picker → bag → `@AppStorage` → `ReminderStore`

1. **Source of truth**: `@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults) var sortOption = SortOption.priority` at `SingleThread/ContentView.swift:118-119` (App Group suite so widget/watch share the key).
2. **Bag creation**: gear button runs `settingsBag = makeSettingsBag(); isShowingSettings = true` (`ContentView.swift:196-197`); `settingsBag` is `@State private var settingsBag: SettingsBindings?` (`:334`), nilled on dismiss (`:288-292`). `makeSettingsBag()` copies current `@AppStorage` values into a fresh `SettingsBindings` (`ContentView+Settings.swift:48-87`; iOS passes `sortOption:` at `:65`, macOS at `:80`).
3. **User edits**: picker writes `$bindings.sortOption` (`FilterSortSettingsView.swift:10,20`), materialized at `SettingsView.swift:94`.
4. **Write-back**: `settingsSheetWritebacks(_:)` (`ContentView+Settings.swift:7-44`) chains `.onChange(of: bag.sortOption) { _, new in sortOption = new }` (`:38`) — assigns the `@AppStorage` property, persisting to `AppGroup.defaults`.
5. **Store application**: main `body` `.onChange(of: sortOption) { _, newValue in viewModel.handleSortOption(newValue) }` (`ContentView.swift:274-276`) → `ContentViewModel.handleSortOption` (`ContentViewModel.swift:126-128`) → `store.setSortOption(option)`.
6. **`ReminderStore.setSortOption`**: `ReminderStore.swift:407-412` guards `option != sortOption`, assigns, fires `onSortOptionChanged?(option)` and `onRemindersChanged?()`. `visibleReminders` computed with `.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }` (`:147-152`).
7. **Shadow persistence**: launch `AppViewModel.init` does `store.sortOption = SortOptionStore().load()` (`AppViewModel.swift:25`); iOS `store.onSortOptionChanged = { option in SortOptionStore().save(option); service.pushAll() }` (`AppViewModel.swift:402-405`) also saves via the store and pushes the watch context.

## 6. Tests

### Unit — model & store
`SingleThreadTests/SortOptionTests.swift`
- Raw values match payload keys (`:9-12`), `allCases` exact `[.priority, .dueDate, .title]` (`:14-16`), `defaultsKey == "sortOption"` (`:18-20`).
- Presentation helpers: titles asserted via `String.en("Priority", bundle: .main)` etc. (`:22-26`; helper in `SingleThreadTests/LocalizationTestHelpers.swift:3-12`), systemImage non-empty (`:28-32`).
- `SortOptionStoreTests` (`:35-55`): missing key → `.priority` (`:37-40`), invalid raw value → `.priority` (`:42-47`), save/load round-trip (`:49-54`) — UUID keys on `.standard`.

### Unit — view structure (reflection-based, no picker interaction)
`SingleThreadTests/SettingsViewTests.swift`
- `settingsViewContainsNavigationLinkLabels` (`:28-58`): root rows incl. "Filtering & Sorting" label + caption "Control the order, visibility, and excluded lists."
- `filterSortSettingsViewContainsExpectedRows` (`:165-189`): builds `FilterSortSettingsView(sortOption: .constant(.priority), showUndatedReminders: .constant(false), availablesLists: ["Work"], excludedLists: .constant([]))`; asserts `String(describing: view.body)` contains "Sort By"/"Show undated reminders"/"Excluded Lists" + three captions; on macOS also asserts `SettingsSubscreenLayout` string (`:182-187`).
- Bag-default tests: e.g. `settingsBindingsCarriesShowCompletionGlow` (`:13-20`) — no `sortOption` bag-default test exists.
- `SettingsViewModelTests.swift:9-25` — crash-guard smoke test (no sort-specific coverage).

### Unit — store behavior & ordering
- `SingleThreadTests/ReminderStoreTests.swift` `setSortOptionReordersAndNotifies` (`:165-217`): default `.priority` order (`:183-185`), `.dueDate` reorders (`:186-189`), hooks fire (`:197-203`), idempotence — three identical sets fire once (`:208-216`).
- `SingleThreadTests/ReminderSkipTests.swift`: `priorityOptionMatchesLegacyComparator` (`:166-173`), `dueDateOptionSortsSoonestFirst` (`:175-185`), `titleOptionSortsCaseInsensitively` (`:187-196`), helper `titles(of:using:)` (`:218-220`).
- `ContentViewModelTests` has **no** `handleSortOption` test.

### UI tests
- **Navigation into the screen**: `SingleThreadUITestsFlows.swift` `testSettingsOpensAndShowsControls` (`:222-251`): taps `"settingsButton"` → `"settingsInterfaceRow"` → back → `"settingsReminderRow"` → back → `app.buttons["settingsFilterSortRow"].tap()` (`:242-243`), asserts `app.staticTexts["Sort By"]` and `app.staticTexts["Excluded Lists"]` exist (`:244-245`). The only FilterSort UI test.
- **No UI test taps or changes the Sort By picker.** No interaction in `SingleThreadUITests/` with the sort picker or its options; picker-driving UI tests exist only for appearance (`SingleThreadUITestsAppearanceLaunchTests.swift:48-116`), text-size, and notification-interval pickers (`NotificationsSettingsUITests.swift:23-38`, `NotificationsUITests.swift:26-100`). No sort-option persistence UI test (`assertTogglePersists` in `SingleThreadUITestCase.swift:45-55` covers toggles only).
- Sort-order UI assertions rely on default `.priority` sort: `testSkipAdvancesToNextReminder` (`SingleThreadUITestsFlows.swift:54-70`), `testPriorityMarkerRendersForMidRangeValue` (`:74-84`).
- `--seed` reset path removes the `"sortOption"` key (`UITestingSeed.swift:83`) so seeded UI tests are deterministic.

## Value/binding chain (data flow)
`Picker` (`FilterSortSettingsView.swift:20-26`) → `$bindings.sortOption` (`SettingsView.swift:94`) → `SettingsBindings.sortOption` (`SettingsBindings.swift:77`) → `.onChange(of: bag.sortOption)` write-back to `@AppStorage(SortOption.defaultsKey, store: AppGroup.defaults)` (`ContentView+Settings.swift:38`; `ContentView.swift:118-119`) → `.onChange(of: sortOption)` (`ContentView.swift:274-276`) → `ContentViewModel.handleSortOption` (`ContentViewModel.swift:126-128`) → `ReminderStore.setSortOption` (`ReminderStore.swift:407-412`) → re-sorted `visibleReminders` (`:147-152`). Shadow persistence: `SortOptionStore().save(option)` + watch push via `onSortOptionChanged` (`AppViewModel.swift:402-405`); load at launch `AppViewModel.swift:25`.