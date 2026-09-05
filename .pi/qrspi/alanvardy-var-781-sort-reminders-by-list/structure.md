# Structure Outline

## Approach

VAR-781 inserts a **list tie-break** into the single shared reminder comparator
(`ReminderSort`), so reminders group by their list (calendar title) inside every
primary bucket. Because all four surfaces render `visibleReminders.first`, the
whole product inherits the change through `ReminderStore.swift:151` — no settings,
persistence, sync, or UI work. Implemented bottom-up: fixture seam → comparator →
full-gate verification.

> **Horizontal note:** there is no schema/store/service/transport layer here — the
> change is a pure, stateless ordering function in `SingleThreadCore`. It is already
> in its bottom-most form; the layers below are the *test foundation* and the *core
> behavior* that depend on it.

---

## Stage 1: Test seam — list-bearing fixture (bottom)

Delivers the fixture helper every later test builds on. No production behavior
changes; this proves the seam is backward-compatible (default `calendarTitle` keeps
`nil` list, so existing tests run unmodified).

**Files**: `SingleThreadTests/ReminderSkipTests.swift`

**Key changes**:
- `makeReminder(title:priority:dateComponents:calendarTitle:) -> EKReminder` — extend the
  existing `makeReminder(_:priority:dateComponents:)` (`:202-212`) with
  `calendarTitle: String? = nil`. When non-nil, build
  `EKCalendar(for: .reminder, eventStore:)`, set `calendar.title = calendarTitle`,
  assign `reminder.calendar`. Never saved through EventKit (matches existing fixture).

**Tests**: existing `ReminderSortTests` (`ReminderSkipTests.swift:134-225`) must stay
green with the default-`nil` fixtures — no new assertions yet, this stage
characterizes "the seam compiles and changes nothing."

**Verify**: `./scripts/test.sh --unit-only` (or targeted
`-only-testing:SingleThreadTests/ReminderSortTests`) — green before advancing.

---

## Stage 2: Comparator — `compareLists` tier + chain threading

Adds the new tier and threads it into all three option chains. This is the entire
production change; the tier is `private` (mirroring `compareDueDates`), so it is
only observable through the public `areInIncreasingOrder(_:_:using:)` and is tested
*through* those entry points.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`,
`SingleThreadTests/ReminderSkipTests.swift`

**Key changes**:
- `private static func compareLists(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult?`
  — new tier. Collates `lhs.calendar?.title` vs `rhs.calendar?.title` via
  `localizedCaseInsensitiveCompare`; returns `nil` on `.orderedSame` or nil-nil
  (falls through), `nil` when one side lacks a list vs a titled side → the titled
  side ascends (nil-list sorts last). Same optional-unwrap shape as
  `compareDueDates` (`ReminderSort.swift:61-74`).
- `areInIncreasingOrder(_:_:using:) -> Bool` — modified switch arms:
  - `.priority` → `comparePriorities` → **`compareLists`** → `compareDueDates` → title
  - `.dueDate` → `compareDueDates` → **`compareLists`** → title
  - `.title` → title → **`compareLists`** → `compareDueDates` → `false`
  Legacy 2-arg `areInIncreasingOrder(_:_:)` unchanged (delegates to `.priority`).

**Tests** (`ReminderSortTests`, names without `test` prefix):
- `groupsByListWithinPriorityBucket` — same rank, different lists → list-ordered (happy)
- `groupsByListWithinDueDateBucket` — same date, different lists → list-ordered
- `groupsByListWithinTitleBucket` — same title, different lists → list before date
- `listCollationIsCaseAndLocaleInsensitive` — `work` vs `Work` collapse (happy)
- `nilListSortsLast` — titled list vs nil list, both orders (sad path)
- `sameListFallsThroughToDateThenTitle` — same list, same primary → date/title tiers still
  decide (sad path: nil-nil and equal-list fall through, not a hard stop)
- Extend `priorityOptionMatchesLegacyComparator` fixtures to carry calendars; the
  `.priority`-option-vs-legacy equivalence must still hold.

**Verify**: `./scripts/test.sh --unit-only` green (targeted fast loop:
`-only-testing:SingleThreadTests/ReminderSortTests`). Do not advance until every
existing unmodified chain test + every new list test passes.

---

## Stage 3: Full-gate verification + PR UI-gap statement

Produces the release-ready artifact: whole gate green, Periphery clean (no dead
`compareLists`), and the explicit PR note per Decision 4 / Open Risks.

**Files**: none (verification + `conventions.md`-documented). Optional: nothing.

**Key changes:**
- Confirm `compareLists` is referenced from all three arms (or Periphery `--strict`
  would flag it dead — the gate catches an unwired tier).
- PR statement: "list grouping is unit-tested only; a deterministic list-grouping UI
  flow requires the deferred `--seed` per-calendar extension
  (`UITestingSeed.swift:145,153` forces the first calendar on every reminder)."

**Tests**: full `./scripts/test.sh` — SwiftFormat → SwiftLint `--strict` → iOS
build-for-testing → watch build → `periphery scan --strict` → iOS unit → iOS UI →
watch build-for-testing → watch UI → watch unit → macOS unit.

**Verify**: `./scripts/test.sh` passes once, end-to-end (do not re-run per stage —
see AGENTS.md "Gate staging").

---

## Testing Checkpoints

1. **After Stage 1** — `./scripts/test.sh --unit-only` green with existing
   `ReminderSortTests` (seam backward-compatible).
2. **After Stage 2** — `./scripts/test.sh --unit-only` green: all new list-grouping
   cases + the unmodified legacy/chain tests + `.priority`==legacy equivalence.
3. **After Stage 3** — `./scripts/test.sh` (full gate) green, Periphery `--strict`
   clean; PR UI-gap statement present.

> **If Stage 2 fails**, Stage 1 (fixture seam) is still independently landable and
> useful. If a later stage reveals a call-site assumption the design missed, stop and
> report rather than patching around it — the design asserted a single call site
> (`ReminderStore.swift:151`); anything contradicting that means re-running `/3_design`.