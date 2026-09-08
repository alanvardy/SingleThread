# Design Discussion

Branch: `alanvardy-var-781-sort-reminders-by-list` · Ticket VAR-781: sort reminders by list.

## Current State

- **One sort, one site.** `ReminderStore.visibleReminders` (`ReminderStore.swift:147-152`) is
  the single production comparator call — `.sorted { ReminderSort.areInIncreasingOrder($0, $1, using: sortOption) }`
  (`:151`), applied after the skipped-ID filter (`:149`) and excluded-list-title filter (`:150`).
  `sortOption` defaults to `.priority` (`ReminderStore.swift:77`). No other production re-sort exists.
- **The comparator** (`SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`) operates on
  `EKReminder` directly. Two entry points: the legacy 2-arg form (`:9-11`, delegates to `.priority`)
  and the option-aware 3-arg form (`:14-42`).
- **Per-option chains today** (`ReminderSort.swift:19-40`):
  - `.priority` → priority rank → due date → title (`:19-26`)
  - `.dueDate` → due date → title (`:27-31`)
  - `.title` → title → due date → `false` (`:32-40`, no identity fallback)
- **Three comparison tiers**, each returning `ComparisonResult?` where `nil` = tie:
  `comparePriorities` (`:46-59`), `compareDueDates` (`:61-74`), `titleComparison` (`:76-78`,
  always decisive via `localizedCaseInsensitiveCompare`). The list/calendar is never consulted.
- **List title is the identity** everywhere it is surfaced — exclusion filter
  (`ReminderStore.swift:150`), `availableLists` (`:480-483`), display `ReminderDisplay.listName`
  (`ReminderDisplay.swift:16`); `calendarIdentifier` appears nowhere in Swift sources.
- **First-element doctrine.** All four surfaces (iOS, watchOS, macOS, widget) render
  `visibleReminders.first` / `listContent` (`ReminderStore.swift:167-168,260-262,315-317,380-382,422`;
  `ContentView.swift:413`; `WatchReminderView.swift:107`; `NextThingWidget.swift:71-75`). Sort order
  *is* product behavior.
- **Tests pin the current chains** (`ReminderSkipTests.swift:134-225`): priority→date→title
  (`:137-149`), same-priority date/title tiers (`:152-162`), option-equivalence of `.priority` vs the
  legacy 2-arg comparator (`:165-173`). Fixtures (`makeReminder`, `:202-212`) set no calendar, so
  every fixture reminder has a nil list.

## Desired End State

After the user-selected primary sort (priority, due date, or title), reminders group by their list
(calendar), so reminders sharing a list stay adjacent within their primary bucket. New chains:

- `.priority` → rank → **list** → due date → title
- `.dueDate` → due date → **list** → title
- `.title` → title → **list** → due date → `false`

Because the change lives entirely in `ReminderSort.swift`, every surface inherits it through
`visibleReminders`/`listContent` with no per-target, no sync, and no settings work.

**Verify correctness by:**
1. Unit tests (Swift Testing, `make test` / `-only-testing:SingleThreadTests`) covering: list groups
   within a primary bucket per option; list collation is case- and locale-insensitive; nil-list sorts
   last; `.priority` option still equals the legacy 2-arg comparator; existing chain tests pass
   unmodified (nil-list fixtures tie on the new tier and fall through).
2. Full gate `./scripts/test.sh` (SwiftFormat → SwiftLint `--strict` → build → Periphery → unit/UI
   suites) — see `conventions.md`.

## Patterns to Follow

- **Tier-pocket composition** — each tier returns `ComparisonResult?` (nil = tie), and the `switch`
  threads them with `if let … { return … == .orderedAscending }` (`ReminderSort.swift:19-40,46-78`).
  New `compareLists` follows the same shape.
- **Optional-unwrap tier** — mirror `compareDueDates` (`ReminderSort.swift:61-74`) for the new tier:
  two `.some` lists compared via `localizedCaseInsensitiveCompare` (ascending); `.some` vs `.none` →
  ascending; `.none` vs `.some` → descending; equal/nil-nil → `nil` (fall through). This is the exact
  "dated sorts before undated" shape (`:67-70`).
- **Collation** — `localizedCaseInsensitiveCompare`, matching `titleComparison`
  (`ReminderSort.swift:76-78`), not the case-sensitive `Set().sorted()` used by `availableLists`
  (`ReminderStore.swift:484`, a dedup/display concern, not user-facing grouping).
- **Nil-last consistency** — nil-list sorts after any real list, matching unranked-priority-last
  (`ReminderSort.swift:54-55`) and undated-last (`:67-70`).
- **Test naming** — Swift Testing, names must not start with `test`/`testing`
  (`preferSwiftTesting` strips the prefix; see AGENTS.md/conventions). Extend `ReminderSortTests`,
  reusing `makeReminder(title:priority:dateComponents:)` (`ReminderSkipTests.swift:202-212`), adding a
  list-bearing fixture helper.
- **Patterns NOT to follow:** the exclusion feature's title-exact-match semantics
  (`ReminderStore.swift:150`) are identity, not collation — do not reuse case-sensitivity there for
  sorting; and do *not* add a `SortOption` case or a new persisted key for the list tie-break.

## Design Decisions

1. **Position of the list tie-break** — list sits immediately after the primary key, demoting the
   existing secondary tiers (Option A). — The ticket's "secondary sort" and "grouped together"
   phrasing only hold if list is decisive right after the primary; a final-fallback position (Option B)
   would essentially never fire because `titleComparison` (`ReminderSort.swift:76-78`) is nearly always
   decisive. Existing chain tests survive because fixtures leave calendar nil, so the new tier ties and
   the chain falls through exactly as before.
2. **List identity and collation** — `calendar?.title` compared via `localizedCaseInsensitiveCompare`
   (Option A). — Matches the established title-as-identity model and `titleComparison` collation;
   case- and locale-insensitive grouping. Duplicate calendar names are disallowed by the system, so
   shared-title risk is theoretical.
3. **Nil-list placement** — reminders without a calendar sort last within their bucket (Option A). —
   Consistent with the existing nil-handling in `compareDueDates`/`comparePriorities`
   (`ReminderSort.swift:54-55,67-70`).
4. **UI-test seam** — do **not** extend the `--seed` schema with per-reminder calendars (Option B). —
   Keeps the change scoped to `ReminderSort.swift` + unit tests; `UITestingSeed`/`AppViewModel` stay
   untouched. Consequence (see Open Risks): list *grouping* is unit-tested only.
5. **Determinism fallback** — no `calendarItemIdentifier` final tie-break (Option A). — Fully-tied
   reminders keep stdlib stable input order, unchanged from today (`ReminderSort.swift:40`); a strict
   total order is out of scope for this ticket.

## What We're NOT Doing

- **No new user-selectable "Sort by List" option** — list is a tie-break only. No `SortOption` case
  (`SortOption.swift:6-19`), no `FilterSortSettingsView` picker entry, no persistence/sync change.
- **No identifier plumbing** — no `calendarIdentifier` reads, no list model, no EventKit change
  observation (consistent with the deliberate absence per the var-750 design note).
- **No seed-schema extension** — `ReminderSeed` (`UITestingSeed.swift`) stays `title`/`notes`/`priority`;
  per-reminder calendars remain unsupported.
- **No identity/stable-order work** — no `calendarItemIdentifier` fallback, no strict-total-order
  property tests.
- **No changes to `availableLists`, exclusion, or list display** — sorting borrows the title, it does
  not touch how lists are named, filtered, or rendered.

## Open Risks

- **UI-coverage gap (from Decision 4).** The ticket requires unit *and* UI tests, but the `--seed` seam
  assigns every reminder the first calendar (`UITestingSeed.swift:145,153`) and resets `sortOption`, so
  a deterministic list-grouping UI test is not stageable without a seam change. The sole existing order
  assertion (`testSkipAdvancesToNextReminder`, `SingleThreadUITestsFlows.swift:54-72`) does not exercise
  list grouping. This must be stated explicitly in the PR ("list grouping is unit-tested only; a new
  UI-flow test requires the deferred `--seed` per-calendar extension"), per AGENTS.md.
- **Title-keyed grouping inherits the title-as-identity caveats.** Two calendars with the same title
  would merge in sort order (same caveat exclusion/display already accept), and a renamed list changes
  its sort grouping on the next `reload()` (recomputed ephemerally, so less sticky than the persistent
  exclusion set — `ReminderStore.swift:150`).
- **Non-determinism on fully-tied reminders** — two reminders with equal primary key, equal list, equal
  date, and case-insensitively equal title remain in stdlib stable input order. Unchanged by this work;
  unasserted today (research "Open Areas").
- **macOS sort/settings surface** is not fully walked in research, but this change is surface-agnostic
  (single shared comparator), so residual risk is low.

Next: run `/4_structure` (after your review below).