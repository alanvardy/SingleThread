# Implementation Plan

## Overview

After the user-selected primary sort (priority, due date, or title), reminders are grouped by their list (calendar title) via a new `compareLists` comparison tier threaded into all three option chains in `ReminderSort`. The change is a pure, stateless ordering function in `SingleThreadCore` — every surface (iOS, watchOS, macOS, widget) inherits it through the single call site `ReminderStore.visibleReminders` (`ReminderStore.swift:151`).

---

## Phase 1: Test seam — list-bearing fixture (bottom)

Deliver the fixture helper every later test builds on. No production behavior change; this proves the seam is backward-compatible (default `calendarTitle` keeps `nil`, so every existing fixture stays list-less and existing tests run unmodified).

### Changes

#### 1. Extend the `makeReminder` fixture helper
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — the private `makeReminder(title:priority:dateComponents:)` helper inside `ReminderSortTests` (currently ~`:202-212`).

Add a trailing `calendarTitle: String? = nil` parameter. When non-nil, build a calendar with `EKCalendar(for: .reminder, eventStore:)`, set its title, and assign it to the reminder. Never saved through EventKit (matches the existing "construction only" pattern, and the identical construction already proven at `UITestingSeed.swift:139-153`).

```swift
    private func makeReminder(
        title: String,
        priority: Int = 0,
        dateComponents: DateComponents? = nil,
        calendarTitle: String? = nil) -> EKReminder {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.priority = priority
        reminder.dueDateComponents = dateComponents
        if let calendarTitle {
            let calendar = EKCalendar(for: .reminder, eventStore: store)
            calendar.title = calendarTitle
            reminder.calendar = calendar
        }
        return reminder
    }
```

No other production or test code changes in this phase. Existing `ReminderSortTests` fixtures omit `calendarTitle`, so `reminder.calendar` stays `nil` and the comparator's existing chains are exercised exactly as before.

### Verification

#### Automated
- [x] `./scripts/test.sh --unit-only` passes (existing `ReminderSortTests` green with default-`nil` fixtures — characterizes "seam compiles and changes nothing")
- [ ] Fast loop (optional during iteration): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=<ver>' -only-testing:SingleThreadTests/ReminderSortTests test` (pin `,OS=<ver>` or `,id=<UDID>` to avoid an ambiguous bare `name=` hang)

#### Manual
- [ ] Confirm no fixture outside `ReminderSortTests` is affected — grep for `makeReminder(` call sites in `SingleThreadTests/` and confirm none pass a 4th argument yet; all compile against the defaulted parameter.

---

## Phase 2: Comparator — `compareLists` tier + chain threading

The entire production change. The tier is `private`, so it is observable only through `areInIncreasingOrder(_:_:using:)` and is tested *through* those entry points.

### Changes

#### 1. Add `compareLists` private tier
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`
**Action**: modify — add a private static function alongside `comparePriorities`/`compareDueDates`, mirroring the optional-unwrap shape of `compareDueDates` (`:61-74`).

Collates `lhs.calendar?.title` vs `rhs.calendar?.title` via `localizedCaseInsensitiveCompare`; returns `nil` on `.orderedSame` or nil-nil (falls through), `.some` vs `.none` → `.orderedAscending` (titled list ascends, nil-list sorts last).

```swift
    private static func compareLists(_ lhs: EKReminder, _ rhs: EKReminder) -> ComparisonResult? {
        let lhsList = lhs.calendar?.title
        let rhsList = rhs.calendar?.title
        switch (lhsList, rhsList) {
        case let (.some(left), .some(right)):
            let comparison = left.localizedCaseInsensitiveCompare(right)
            return comparison == .orderedSame ? nil : comparison
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return nil
        }
    }
```

#### 2. Thread `compareLists` into `areInIncreasingOrder(_:_:using:)`
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderSort.swift`
**Action**: modify — insert `compareLists` immediately after the primary key in each of the three switch arms (demoting the existing secondary tiers).

`.priority` arm (list after rank, before date):

```swift
        case .priority:
            if let rank = comparePriorities(lhs, rhs) {
                return rank == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
```

`.dueDate` arm (list after date, before title):

```swift
        case .dueDate:
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            return titleComparison(lhs, rhs) == .orderedAscending
```

`.title` arm (list after title, before date):

```swift
        case .title:
            let comparison = titleComparison(lhs, rhs)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            if let list = compareLists(lhs, rhs) {
                return list == .orderedAscending
            }
            if let date = compareDueDates(lhs, rhs) {
                return date == .orderedAscending
            }
            return false
```

The legacy 2-arg `areInIncreasingOrder(_:_:)` (`:9-11`) is unchanged — it delegates to `.priority`, which now includes the list tier.

> Run `make format` after editing — `organizeDeclarations` may reposition `compareLists` among the private functions; the gate enforces the final ordering.

#### 3. New comparator unit tests
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — add six test functions to `struct ReminderSortTests` (names must **not** start with `test`/`testing` — SwiftFormat's `preferSwiftTesting` would rename them). Reuse the extended `makeReminder` and the existing `titles(of:)`/`titles(of:using:)` helpers. Add one direct-`sorted` assertion where titles collide.

```swift
    @Test
    func groupsByListWithinPriorityBucket() {
        let work = makeReminder(title: "Work task", priority: 1, calendarTitle: "Work")
        let home = makeReminder(title: "Home task", priority: 1, calendarTitle: "Home")
        #expect(titles(of: [work, home]) == ["Home task", "Work task"], "same priority groups by list")
    }

    @Test
    func groupsByListWithinDueDateBucket() {
        let work = makeReminder(title: "Work task", dateComponents: date(2), calendarTitle: "Work")
        let home = makeReminder(title: "Home task", dateComponents: date(2), calendarTitle: "Home")
        #expect(titles(of: [work, home], using: .dueDate) == ["Home task", "Work task"], "same due date groups by list")
    }

    @Test
    func groupsByListWithinTitleBucket() {
        let homeLater = makeReminder(title: "Same", dateComponents: date(10), calendarTitle: "Home")
        let workSooner = makeReminder(title: "Same", dateComponents: date(2), calendarTitle: "Work")
        let sorted = [homeLater, workSooner].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .title) }
        #expect(sorted.map(\.calendar?.title) == ["Home", "Work"], "same title groups by list; list beats due date")
    }

    @Test
    func listCollationIsCaseAndLocaleInsensitive() {
        let upper = makeReminder(title: "z-title", priority: 1, calendarTitle: "Work")
        let lower = makeReminder(title: "a-title", priority: 1, calendarTitle: "work")
        // Case-sensitive would order "Work" before "work"; case-insensitive ties
        // them so title decides. Locale-insensitivity is inherited from
        // localizedCaseInsensitiveCompare (not deterministically assertable here).
        let sorted = [upper, lower].sorted { ReminderSort.areInIncreasingOrder($0, $1, using: .priority) }
        #expect(sorted.map(\.title) == ["a-title", "z-title"], "Work/work collapse to one list; title breaks the tie")
    }

    @Test
    func nilListSortsLast() {
        let titled = makeReminder(title: "titled", priority: 1, calendarTitle: "Work")
        let untitled = makeReminder(title: "untitled", priority: 1)
        #expect(titles(of: [untitled, titled]) == ["titled", "untitled"], "titled list before nil list")
        #expect(titles(of: [titled, untitled]) == ["titled", "untitled"], "nil list sorts last regardless of input order")
    }

    @Test
    func sameListFallsThroughToDateThenTitle() {
        let later = makeReminder(title: "later", priority: 1, dateComponents: date(10), calendarTitle: "Work")
        let sooner = makeReminder(title: "sooner", priority: 1, dateComponents: date(2), calendarTitle: "Work")
        #expect(titles(of: [later, sooner]) == ["sooner", "later"], "same list falls through to date")
        let beta = makeReminder(title: "Beta", priority: 1, calendarTitle: "Work")
        let alpha = makeReminder(title: "Alpha", priority: 1, calendarTitle: "Work")
        #expect(titles(of: [beta, alpha]) == ["Alpha", "Beta"], "same list + no date falls through to title")
    }
```

#### 4. Extend the `.priority`-==-legacy equivalence fixture
**File**: `SingleThreadTests/ReminderSkipTests.swift`
**Action**: modify — the existing `priorityOptionMatchesLegacyComparator` test now carries calendars on both fixtures, proving the `.priority`-option-vs-legacy equivalence holds with list metadata present (priority still decisive, list never consulted here).

```swift
    @Test
    func priorityOptionMatchesLegacyComparator() {
        let lowPriority = makeReminder(title: "a", priority: 9, dateComponents: date(2), calendarTitle: "Work")
        let highPriority = makeReminder(title: "b", priority: 1, calendarTitle: "Home")
        let viaPriority = [lowPriority, highPriority].sorted {
            ReminderSort.areInIncreasingOrder($0, $1, using: .priority)
        }.map(\.title)
        let viaLegacy = [lowPriority, highPriority].sorted { ReminderSort.areInIncreasingOrder($0, $1) }.map(\.title)
        #expect(viaPriority == viaLegacy)
    }
```

### Verification

#### Automated
- [x] `./scripts/test.sh --unit-only` passes — all six new list-grouping cases **and** every pre-existing unmodified chain test (`sortsByPriorityThenDateThenTitle`, `sortsWithinSamePriorityByDateThenTitle`, `dueDateOptionSortsSoonestFirst`, `titleOptionSortsCaseInsensitively`) stay green
- [ ] Fast loop (optional during iteration): `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=<ver>' -only-testing:SingleThreadTests/ReminderSortTests test`

#### Manual
- [ ] Confirm the three switch arms each invoke `compareLists` exactly once, in the position prescribed (primary → list → secondary → title/`false`)
- [ ] Confirm the legacy 2-arg comparator is untouched and still delegates to `using: .priority`

---

## Phase 3: Full-gate verification + PR UI-gap statement

Produces the release-ready artifact. No source files change here; this is verification plus the explicit PR note required by Decision 4 / Open Risks.

### Changes

#### 1. Periphery dead-code check
**File**: none
**Action**: verify — `compareLists` must be referenced from all three switch arms. The full gate's `periphery scan --strict` flags an unwired private function as dead, so a clean Periphery run confirms the tier is threaded into every chain.

#### 2. PR description note (UI-coverage gap)
**File**: none (PR body text)
**Action**: include this statement verbatim or equivalent in the PR:

> List grouping is unit-tested only; a deterministic list-grouping UI flow requires the deferred `--seed` per-calendar extension (`UITestingSeed.swift:145,153` forces the first calendar on every reminder). No `--seed` schema change was made in this ticket (per design Decision 4), so no UI test exercises list grouping.

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes once, end-to-end (SwiftFormat → SwiftLint `--strict` → iOS build-for-testing → watch build → `periphery scan --strict` → iOS unit → iOS UI → watch build-for-testing → watch UI → watch unit → macOS unit)
- [ ] `make periphery` clean (no dead `compareLists`)

> Do **not** re-run the full gate per phase — per AGENTS.md "Gate staging", the full `./scripts/test.sh` runs ONCE after phases commit. Phases 1–2 use the `--unit-only` / targeted-suites loops above.

#### Manual
- [ ] PR description contains the UI-gap statement from Phase 3.2
- [ ] Confirm `make format` (`organizeDeclarations`) left no pending formatting diff and `swiftlint lint --strict` is clean

---

## Notes / Deviations

- **No deviations from `structure.md`.** Phase order, file scope, and the "bottom-up: fixture seam → comparator → full gate" shape are preserved exactly.
- **Locale assertion nuance**: `listCollationIsCaseAndLocaleInsensitive` (structure Stage 2) asserts case-insensitivity directly; locale-insensitivity is inherited from `localizedCaseInsensitiveCompare` and is not deterministically assertable in a localized unit test (no fixed `Locale` is injected), so the body documents this rather than over-asserting. Same test name as the structure requested.
- **UI-test tension resolved by the design**: the ticket's "unit and UI tests" requirement is met at the unit level; the UI gap is an explicit, pre-agreed PR statement (Decision 4), not a new UI test.