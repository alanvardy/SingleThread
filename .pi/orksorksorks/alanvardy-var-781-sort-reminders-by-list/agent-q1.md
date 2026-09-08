# Agent Q1 — Sort comparator architecture

## 1. Comparator entry points

`ReminderSort` is a `public nonisolated enum` (`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift:4`) with two comparators:

- **Legacy 2-arg overload** — `areInIncreasingOrder(_ lhs: EKReminder, _ rhs: EKReminder)` at `ReminderSort.swift:9-11`. Pure delegate: `areInIncreasingOrder(lhs, rhs, using: .priority)` (`:10`). Doc comment labels it "backward-compatible" to the legacy compound order priority → due date → title (`:7-8`).
- **Option-aware 3-arg overload** — `areInIncreasingOrder(_:_:using:)` at `ReminderSort.swift:14-17`, dispatching on `option` (`:18`).

Both `static`/pure and `nonisolated`; the only production call site is `ReminderStore.visibleReminders` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:147-152`):

```swift
reminders
    .filter { !skippedIDs.contains($0.calendarItemIdentifier) }
    .filter { !excludedListTitles.contains($0.calendar?.title ?? "") }   // :150
    .sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }   // :151
```

`sortOption` defaults to `.priority` (`ReminderStore.swift:77`); `setSortOption` fires hooks only on change (`ReminderStore.swift:407-412`).

## 2. Composition machinery: three comparison "tiers"

Every tier returns an optional `ComparisonResult` where `nil` means "tied at this tier", letting the next tier decide.

### Tier A — priority rank — `comparePriorities` (`ReminderSort.swift:46-59`)
- Ranks both reminders via `ReminderPriority.rank(for:)` (`ReminderSort.swift:47-48`), defined at `SingleThreadCore/Sources/SingleThreadCore/ReminderSkip.swift:82-89`: `high`→`0`, `medium`→`1`, `low`→`2`, `nil` for `0`/out-of-range (via `level(for:)` at `ReminderSkip.swift:60-67`, which maps `1...4`→high, `5`→medium, `6...9`→low, `default`→nil).
- `ReminderSort.swift:50-51`: both ranked and ranks differ → lower rank ascends (high 0 < medium 1 < low 2).
- `ReminderSort.swift:52-53`: `.some` vs `.none` → ranked reminder ascends (ranked before no-priority).
- `ReminderSort.swift:54-57`: `.none` vs `.some` → descends; both ranked equal or both `nil` → `nil` (tie, fall through).

### Tier B — due date — `compareDueDates` (`ReminderSort.swift:61-74`)
- Reads `lhs.dueDateComponents?.date` / `rhs.dueDateComponents?.date` (`:62-63`).
- `ReminderSort.swift:65-66`: both dated and unequal → earlier date ascends.
- `ReminderSort.swift:67-68`: dated vs undated → dated ascends (dated before undated).
- `ReminderSort.swift:69-72`: undated vs dated → descends; both undated or equal dates → `nil` (tie, fall through).

### Tier C — title — `titleComparison` (`ReminderSort.swift:76-78`)
`lhs.title.localizedCaseInsensitiveCompare(rhs.title)` — non-optional, always decisive.

## 3. Composition per `SortOption` case (`ReminderSort.swift:19-40`)

| Option | Primary key | Tie-break chain | Final fallback |
|---|---|---|---|
| `.priority` (`:19-26`) | priority rank (`:20-21`) | due date (`:23-24`) | title (`:26`) |
| `.dueDate` (`:27-31`) | due date (`:28-29`) | — | title (`:31`) — **priority is never consulted** |
| `.title` (`:32-40`) | title (`:33-35`) | due date (`:37-38`) | `return false` (`:40`) when title **and** date tie |

Notes:
- In `.title` mode, if `titleComparison != .orderedSame` the title decides (`.title` also ignores priority); only on `.orderedSame` does due date break the tie; if that also ties (both nil or equal dates), the comparator returns `false` — i.e., the two reminders are order-equivalent, with **no identity tie-break** (e.g., no `calendarItemIdentifier` key).
- In `.priority`/`.dueDate` mode, title is the terminal tier and always decides (titles compare unequal via `localizedCaseInsensitiveCompare` unless identical/equal under the current locale).
- Reflexivity: `areInIncreasingOrder(a, a)` is `false` in every mode (priority/date tiers return `nil`, title returns `.orderedSame`, `.title` hits `:40`).

The enum itself is closed and ordered: `public enum SortOption: String, CaseIterable, Sendable` with exactly `priority`, `dueDate`, `title` and shared key `defaultsKey = "sortOption"` (`SingleThreadCore/Sources/SingleThreadCore/SortOption.swift:6-19`); `SortOptionStore.load()` falls back to `.priority` (`SortOption.swift:34-38`), `save` writes the raw value (`:41-43`). The comparator reads `EKReminder` fields under a documented MainActor safety invariant (`SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift:15-18`).

Branch context: on this branch (HEAD `941be95`; parent `d50a155` "Sort reminders by list" only added a `DELETEME` placeholder), `SortOption` has exactly those three cases and `ReminderSort` has no list/calendar key — no list-based sort mode exists in the comparator yet. Working tree is clean.

## 4. Invariants pinned by the comparator unit tests

`struct ReminderSortTests` lives in `SingleThreadTests/ReminderSkipTests.swift:134-225`. All assertions produce arrays via Swift's stable `sorted(by:)` then map to titles (helpers at `:214-220`).

1. **`sortsByPriorityThenDateThenTitle`** (`ReminderSkipTests.swift:137-149`) — through the legacy 2-arg comparator: high(1) before low(9) (`:138-141`); full rank ladder "H"(1) → "M"(5) → "L"(9) (`:142-145`); prioritized before no-priority, a reminder with default `priority: 0` (`:146-149`).
2. **`sortsWithinSamePriorityByDateThenTitle`** (`:152-162`) — same priority → earlier date first (`:153-156`); dated before undated (`:156-158`); alphabetical title tie-break "Alpha" before "Beta" among undated same-priority reminders (`:159-161`).
3. **`priorityOptionMatchesLegacyComparator`** (`:165-173`) — **option equivalence**: `.sorted{ using: .priority }` and `.sorted{ 2-arg }` produce identical title arrays (`:168-172`).
4. **`dueDateOptionSortsSoonestFirst`** (`:176-185`) — `.dueDate` **ignores priority** (priority-9 "sooner" before priority-1 "later" by date, `:177-181`); dated before undated (`:182-184`).
5. **`titleOptionSortsCaseInsensitively`** (`:188-197`) — `.title` ignores priority (`:189-191`); case-insensitive alphabetical ("apple" before "Zebra"); equal titles tie-break by due date — day 2 element at `sorted[0]`, day 10 at `sorted[1]` (`:192-196`).

What the tests do **not** pin down:
- No property-based checks of the strict-total-order laws (irreflexivity / antisymmetry / transitivity) or of the reflexive `(a, a)` case.
- **Determinism of fully equal reminders** (identical title + equal/nil dates) is not asserted; the comparator returns `false` in both directions (`ReminderSort.swift:40`), so relative order of such pairs is delegated to the stdlib's stable `sorted(by:)` input-order preservation, not to the comparator.
- Nil-title behavior is unexercised — the fixture `makeReminder(title:priority:dateComponents:)` always sets `title` (`ReminderSkipTests.swift:202-212`).

**Adjacent ordering tests** (not in the comparator suite but pinning the same behavior):
- `ReminderStoreTests.visibleRemindersSortsByPriorityThenDate` (`SingleThreadTests/ReminderStoreTests.swift:51-72`): store-level — priority first, dated before undated at equal priority.
- `ReminderStoreTests.setSortOptionReordersAndNotifies` (`:168-217`): default `.priority` (`:185`), reorder on `.dueDate` (`:186-190`), hook firing, and idempotency (three identical `setSortOption(.title)` → one notification, `:211-216`).
- `SortOptionTests` (`SingleThreadTests/SortOptionTests.swift:8-36`): pins raw values (`:8-12`), `allCases == [.priority, .dueDate, .title]` (`:15-17`), `defaultsKey` (`:20-22`), presentation labels/icons (`:25-36`).
- UI flow comment in `SingleThreadUITestsFlows.swift:113-117`: seeds priorities in **distinct rank buckets** (1–4, 5, 6–9) "or the sort's title tie-break can reorder them" — an explicit acknowledgment that ties fail through to the title tier.

## 5. Data/mutation flow summary

`SortOptionStore.load()`/`@AppStorage`/`setSortOption` → `ReminderStore.sortOption` (`ReminderStore.swift:77`) → `visibleReminders` filters skipped + excluded-list titles then `.sorted(ReminderSort.areInIncreasingOrder(using:))` (`ReminderStore.swift:148-151`) → lexicographic tier chain (priority → due date → title, or date → title, or title → date → equal) on raw `EKReminder` fields `priority`, `dueDateComponents?.date`, `title` — never on calendar/list identity.