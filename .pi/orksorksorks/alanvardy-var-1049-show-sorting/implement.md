# Implementation Summary

Add a "View sorted and filtered list" row to the Filtering & Sorting settings
subscreen that pushes a read-only, scrollable list of every reminder visible
under the current sort/filter settings, plus row context and an empty state.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `54546af2` | feat(VAR-1049): push sorted and filtered reminder list from settings |
| 2     | `6bca14c2` | feat(VAR-1049): add reminder context rows and empty state to the list preview |

## Automated Checks

- [x] `make build` passes
- [x] `scripts/test-one.sh SingleThreadTests/FilteredRemindersListViewTests` — 5 cases (2 + 3)
- [x] `scripts/test-one.sh SingleThreadTests/FilterSortSettingsViewTests` — 8 cases
- [x] `scripts/test-one.sh SingleThreadTests/SettingsViewTests` — 15 cases
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` — 5 cases (proves all 6 languages on all 4 new keys, no English-identity values)
- [x] `make format` clean (no staged swiftformat diff)
- [x] `make lint` clean (0 violations in 207 files)

## What changed

**Phase 1 — walking skeleton**
- New `SingleThread/FilteredRemindersListView.swift`: pushed read-only `Form` list of `ReminderDisplay` titles (uses `enumerated()` + `id: \.offset` since `ReminderDisplay` is Equatable, not Identifiable), `.localizedNavigationTitle("Sorted & Filtered")`, `.settingsSubscreenLayout()`, preview.
- `FilterSortSettingsView.swift`: added `let store: ReminderStore` input + `listDisplays` (maps `store.visibleReminders` → `ReminderDisplay` rows), new NavigationLink `Section` after Excluded Lists, store arg in `#Preview("Default")`.
- `SettingsView.swift`: threaded `store` into `init`, added `private let store: ReminderStore`, passes it into `FilterSortSettingsView`, store args in both previews.
- `ContentView+Settings.swift`: added `store: viewModel.store,` at the sheet call site. No `ContentView.swift` change.
- `Localizable.xcstrings`: 3 new keys × 6 languages (`Sorted & Filtered`, `View sorted and filtered list`, `Preview how your reminders are ordered right now.`).
- `TestFixtures.swift`: `makeEmptyReminderStore()` (`@MainActor`, `InMemoryEventStore`, `loadsReminders: false`).
- New `FilteredRemindersListViewTests.swift` (2 tests); `FilterSortSettingsViewTests.swift` (store arg × 8 constructions, updated expected labels/captions, 2 new wiring tests); `SettingsViewTests.swift` (store arg).

**Phase 2 — row context + empty state**
- `FilteredRemindersListView.swift`: body now handles empty set (`"No reminders match the current filters."` with `.accessibilityIdentifier("filteredRemindersEmptyState")`) vs. `row(for:)` per display; added private `caption(for:)` (list · due date · priority marker, plain `Text` with caption styling since it's a runtime-composed `String`) and `row(for:)` (title + caption, `.accessibilityElement(children: .combine)`, `.accessibilityIdentifier("filteredRemindersRow")`). Preview row exercises all three caption parts.
- `Localizable.xcstrings`: 4th key `No reminders match the current filters.` × 6 languages.
- `FilteredRemindersListViewTests.swift`: 3 new tests (`...ExplainsAnEmptySet`, `...CaptionCarriesListAndPriority`, `...OmitsAbsentCaptionParts`).

## Observations / divergences noted during implementation

- **`import EventKit` added to `FilterSortSettingsViewTests.swift`**: the plan's test snippet used `calendarItemIdentifier` and `.fullAccess` (EventKit members) without the import; the build fails with `#MemberImportVisibility` otherwise. This matches existing convention in `ReminderStoreTests.swift`/`ContentViewModelTests.swift`.
- **`ReminderDisplay` init is positional in declaration order** (`title, notes, dueDate, priorityMarker, listName`): the plan's preview/test snippets placed `listName` before `dueDate`, which Swift rejects. Ordered correctly; the all-three-caption preview row was also wrapped to stay under the 120-char lint limit.
- **Simulator contention during phase 2 verification**: a concurrent worktree (`var-1023` running CheckStitch tests) repeatedly monopolized the shared simulator, hanging unit-test runs. Not a code issue; runs passed once it cleared. Suggested `SIM` pinning with the `env` prefix (fish) against UDID `2BD7F165-...`.
- **`plan.md` was untracked at Phase 1** (not in commit `54546af2`); it landed in the Phase 2 commit `6bca14c2` with both Phases' checkboxes. `medium.md` remains untracked. If the intent was for plan.md to land in Phase 1's commit, that can be adjusted in review.

## Manual Verification Items (from the plan)

- [ ] Xcode → iOS app on `iPhone 17`: gear (`settingsButton`) → Filtering & Sorting → **View sorted and filtered list**. Pushed screen titled "Sorted & Filtered" lists every reminder the main card would cycle through, in current sort order.
- [ ] Set Sort By to a different option, go back, re-enter the list: order matches the new setting.
- [ ] Toggle "Show undated reminders" off, re-enter: undated reminders absent from the list.
- [ ] Xcode preview of `FilteredRemindersListView` renders the three sample rows.
- [ ] Run iOS app; open the list with a reminder that has a list and a due date: row shows title plus a "List · date" caption line.
- [ ] Skip every visible reminder (or exclude the only list), re-enter: shows "No reminders match the current filters."
- [ ] `#Preview("Default")` of `FilterSortSettingsView` still renders the Excluded Lists row and the new row.