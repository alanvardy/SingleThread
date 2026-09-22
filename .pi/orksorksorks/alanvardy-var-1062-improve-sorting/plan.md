# Implementation Plan

## Overview

Add a selectable **Default** `SortOption` (raw API order, no reordering) and rework the
`ReminderSort` comparator chains to the ticket's rules (`.priority`: priority → due date →
title; `.title`: title only; `.dueDate`: due date → priority → title; `.default`: no
reordering). The enum case forces three exhaustive switches to be updated, and
`ReminderStore.visibleReminders` gains a `.default` short-circuit so phone, watch, widget
and intents all inherit raw order through the shared Core path. Two commits: (1) the
functional walking skeleton, (2) persistence/sync proof plus the localized label.

### Decisions locked by this plan (recon-driven; see summary for confirmation)

- **Drop the `compareLists` tie-break entirely.** The ticket enumerates complete chains
  ("Sort by title just sorts by title"), and the current `compareLists` step is not in the
  spec. The now-unused `ReminderSort.compareLists` private helper is deleted (Periphery
  would otherwise flag it), and the three `groupsByListWithin*` tests plus the list-collation
  tests are removed.
- **Keep the store fallback at `.priority`.** `SortOptionStore.load()`/`save()` and the
  `ReminderStore`/`PreferenceHolder` initial values stay `.priority` — "keep load/save
  backward compatible" — so existing users who never chose a sort keep Priority. `.default`
  is selectable and, once chosen, persists and syncs as raw value `"default"`.
- **`.default` is first in `menuOptions`** (`[.default, .priority, .dueDate, .title]`).
- **Localization**: add an `en` entry for "Default" to the string catalog only; other
  locales fall back to English until the translation flow fills them in.

---

## Phase 1: Core `.default` option + reworked comparator chains (walking skeleton)

The thinnest end-to-end path: the new enum case is offered by the picker, selected through
the store, and makes `visibleReminders` return the raw API order. Adding the case breaks
compilation until every exhaustive switch is handled, so all switch sites land together.

### Changes

#### 1. Add the `.default` case
**File**: `SingleThreadCore/Sources/SingleThreadCore/SortOption.swift`
**Action**: modify

```swift
public enum SortOption: String, CaseIterable, Sendable {
    /// Raw API order: items are shown in the order the API provides them.
    /// The no-reordering baseline, offered first in the sort menu.
    case `default`
    /// Priority rank → due date → title.
    case priority
    /// Due date soonest-first (dated before undated) → priority → title.
    case dueDate
    /// Case-insensitive title A→Z, title only.
    case title
    /// ... (unchanged `.ai` documentation)
    case ai

    public static let defaultsKey = "sortOption"

    /// The options the sort menu offers, in display order. `.ai` stays absent
    /// while on-device AI sorting is disabled.
    public static let menuOptions: [Self] = [.default, .priority, .dueDate, .title]
```

`case default` requires the backtick spelling `` case `default` `` (verified: `rawValue`
is `"default"`, and call sites use `.default` without backticks). `.default` becomes
`isSelectable` automatically because it is in `menuOptions`, so the existing generic
`load()`/`save()` and the sync `isSelectable` gate need no change.

#### 2. Rework the comparator chains and drop `compareLists`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`
**Action**: modify

```swift
switch option {
case .priority, .ai:
    if let rank = comparePriorities(lhs, rhs) {
        return rank == .orderedAscending
    }
    if let date = compareDueDates(lhs, rhs) {
        return date == .orderedAscending
    }
    return titleComparison(lhs, rhs) == .orderedAscending
case .dueDate:
    if let date = compareDueDates(lhs, rhs) {
        return date == .orderedAscending
    }
    if let rank = comparePriorities(lhs, rhs) {
        return rank == .orderedAscending
    }
    return titleComparison(lhs, rhs) == .orderedAscending
case .title:
    return titleComparison(lhs, rhs) == .orderedAscending
case .default:
    return false
}
```

Delete the private `compareLists(_:_:)` helper (its only callers are the three chains
above). Update the `SortOption/priority` doc comment on `areInIncreasingOrder(_:_:)` only
if the chain wording changed; the legacy entry point still delegates to `.priority`.

#### 3. Skip sorting for `.default`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify (`visibleReminders`, ~line 173)

```swift
public var visibleReminders: [EKReminder] {
    let filtered = filteredReminders
    guard sortOption != .default else { return filtered }
    guard sortOption == .ai, !aiRanking.isEmpty else {
        return filtered.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }
    }
    // ... AI-ranked branch unchanged
}
```

This is the single enforcement point for phone, watch, widget and intents — they all read
the shared `visibleReminders`.

#### 4. Present the new option
**File**: `SingleThread/SortOption+Presentation.swift`
**Action**: modify

```swift
case .default: LocalizedStringResource("Default", table: "Localizable", bundle: .main)
...
case .default: "arrow.up.arrow.down"
```

#### 5. Update and extend tests

**File**: `SingleThreadTests/SortOptionTests.swift` — modify
- `rawValuesMatchPayloadKeys`: add `#expect(SortOption.default.rawValue == "default")`.
- `allCasesCoverAllOptions`: expected value becomes `[.default, .priority, .dueDate, .title, .ai]` (declaration order).
- `menuOptionsWithholdTheDisabledAIOption` → expected `[.default, .priority, .dueDate, .title]`, add `#expect(SortOption.default.isSelectable)`, keep `!ai.isSelectable` and the per-case checks.
- `presentationTitlesAreHumanReadable`: add `#expect(SortOption.default.title.resolved(in: Locale(identifier: "en")) == "Default")`.
- `presentationSystemImagesAreValidSFSymbols`: add `#expect(!SortOption.default.systemImage.isEmpty)`.

**File**: `SingleThreadTests/ReminderSkipTests.swift` (`ReminderSortTests`) — modify
- `dueDateOptionSortsSoonestFirst`: keep the soonest-first assertion but fix the stale
  comment (priority is now a tie-break, not ignored); add a same-due-date case where the
  higher-priority reminder sorts first (`date(2)` for both, priority 1 before priority 9).
- `titleOptionSortsCaseInsensitively`: keep the case-insensitive assertion; delete the
  same-title "breaks tie by due date" assertions (title-only now).
- Delete `groupsByListWithinPriorityBucket`, `groupsByListWithinDueDateBucket`,
  `groupsByListWithinTitleBucket`, `listCollationIsCaseAndLocaleInsensitive`,
  `nilListSortsLast`, `sameListFallsThroughToDateThenTitle` — all exercise the removed
  `compareLists`. Date/title fall-through within a priority bucket stays covered by
  `sortsWithinSamePriorityByDateThenTitle`.
- Add `defaultOptionDoesNotReorder`: for distinct reminders,
  `ReminderSort.areInIncreasingOrder(a, b, using: .default) == false` and the reverse is
  also `false`.

**File**: `SingleThreadTests/ReminderStoreTests.swift` — modify (add after `setSortOptionDueDateReordersVisibleReminders`)
- Add `defaultOptionPreservesProvidedOrder`: build a store with reminders supplied in
  unsorted order (e.g. titles `["C", "A", "B"]`), call `setSortOption(.default)`, and assert
  `visibleReminders.map(\.title) == ["C", "A", "B"]`. This is the real end-to-end proof that
  the raw API order survives (`InMemoryEventStore` + `loadsReminders: false`).

**File**: `SingleThreadTests/FilterSortSettingsViewTests.swift` — modify
- `filterSortSettingsViewChoicesExcludeDisabledAI`: expected `view.sortOptionChoices ==
  [.default, .priority, .dueDate, .title]`; keep `!contains(.ai)`.

### Verification

#### Automated
- [x] `make format`
- [x] `make lint` (SwiftFormat lint + `swiftlint lint --strict`)
- [x] `make build`
- [x] `scripts/test-one.sh SingleThreadTests/SortOptionTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderSortTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/ReminderStoreTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/FilterSortSettingsViewTests` passes

#### Manual
- [ ] Run the app, open Settings → Filter & Sort, confirm "Default" appears first with its
      symbol, is selectable, and survives relaunch (persisted as `"default"`).
- [ ] With "Default" selected, confirm the list shows reminders in the API order; switch to
      the other three options and confirm the new chains (title-only ignores priority/date).

---

## Phase 2: Persistence/sync proof + localized label

No functional code change beyond the string catalog: this phase proves `.default` survives
the App Group store and the phone→watch sync, and ships the localized label.

### Changes

#### 1. Store round-trip test
**File**: `SingleThreadTests/SortOptionTests.swift` (`SortOptionStoreTests`) — modify
- Add `saveAndLoadRoundTripsDefault`: with a unique `UserDefaults.standard` key, `save(.default)`
  then `#expect(store.load() == .default)`. Proves `.default` is selectable (not coerced to
  `.priority`). Keep the existing `.ai` degradation tests unchanged.

#### 2. Sync round-trip tests
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift` — modify
- Add `receivesAndPersistsDefaultSortOption`: call
  `service.session(WCSession.default, didReceiveApplicationContext: ["sortOption": "default"])`
  and assert `received == .default` and `sortStore.load() == .default`.
- Add `sendsDefaultSortOption`: `sortStore.save(.default)` before the send path and assert the
  pushed context carries `"sortOption" == "default"`, mirroring the existing `"dueDate"` test
  at ~line 64–82.

#### 3. Localized label
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify

Insert a `"Default"` key immediately before the `"Due Date"` entry (alphabetical order,
~line 4903), matching the catalog's shape:

```json
"Default": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Default" } }
  }
},
```

Other locales intentionally fall back to English; do not invent translations.

### Verification

#### Automated
- [x] `make format`
- [x] `make lint`
- [x] `make build`
- [x] `scripts/test-one.sh SingleThreadTests/SortOptionStoreTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/SkippedReminderSyncServiceTests` passes
- [x] `python3 -c 'import json;json.load(open("SingleThread/Resources/Localizable.xcstrings"))'`
      succeeds (catalog is valid JSON)

#### Manual
- [ ] Pick "Default" on the phone, then confirm the watch reflects the same selection after
      a sync (or in the simulator with the paired watch) and shows raw API order.

---

## Final gate (after both phases commit)

- [ ] Run the full CI-identical gate ONCE via the `run-gate` skill (`./scripts/test.sh`,
      async gate subagent) — never ad-hoc, never per-phase. CI is authoritative for the
      iPhone/iPad matrix.