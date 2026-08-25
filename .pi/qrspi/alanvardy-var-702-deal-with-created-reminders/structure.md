# Structure Outline

## Approach

Merge `ReminderStore`'s two inits into a single init with all parameters defaulted,
then back every test call site with an injected `InMemoryEventStore` so no test
can ever persist to a real Apple Reminders database. The `InMemoryEventStore` gap
(calendar ≠ `defaultCalendarForNewReminders()`) is fixed first as a standalone
building block.

---

## Phase 1: `InMemoryEventStore` calendar fidelity

**What it delivers**: `InMemoryEventStore.makeReminder` assigns the calendar the
same way the real store does — via a `defaultCalendar:` parameter, falling back
to `calendars.first`. The `MakeReminderTests` suite switches to the in-memory
fake so those tests no longer touch a real `EKEventStore`.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`,
`SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
- `InMemoryEventStore.init(reminders:calendars:deliverCompletionOffMain:defaultCalendar:)` — new `defaultCalendar: EKCalendar? = nil` parameter
- `InMemoryEventStore.makeReminder(title:notes:dueDate:recurrenceRule:) -> EKReminder` — uses `defaultCalendar ?? calendars.first` instead of `calendars.first`
- Five `MakeReminderTests` (`ReminderStoreTests.swift:443–492`) switch from `(EKEventStore() as any EventKitStoring).makeReminder(...)` to `InMemoryEventStore().makeReminder(...)`
- New test `makeReminderUsesDefaultCalendar` verifies the `defaultCalendar:` parameter is wired
- `makeReminderSetsDefaultCalendar` (:502–509) stays on the real store with a `// Tests real EventKit calendar behavior` comment

**Verify**:
```bash
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadTests/ReminderStoreTests/MakeReminderTests
```
plus `grep -c 'EKEventStore() as any EventKitStoring).makeReminder' SingleThreadTests/ReminderStoreTests.swift` → `1` (only `makeReminderSetsDefaultCalendar` remains).

---

## Phase 2: Single `ReminderStore` init + all call sites

**What it delivers**: `ReminderStore` exposes exactly one public init.
Every test and preview injects `InMemoryEventStore` (or `FakeEventStore`, where
it already does); no code path can accidentally route a `save`/`remove` to a
real `EKEventStore`. The pre-populate init is deleted.

**Files**:
- `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` — merged init
- `SingleThreadTests/ReminderStoreTests.swift` — ~30 call sites
- `SingleThreadTests/ActionButtonTests.swift` — 3 call sites (:79, 98, 117)
- `SingleThreadTests/ReminderDictationTests.swift` — 1 call site (:176)
- `SingleThreadTests/BackgroundCardTests.swift` — 1 call site (:131)
- `SingleThreadTests/UITestingSeedTests.swift` — 1 call site (:53)
- `SingleThreadTests/EventKitStoringTests.swift` — 3 call sites (:251, 399, 467)
- `SingleThreadTests/SkippedReminderSyncServiceTests.swift` — ~10 call sites (:400, 410, 438, 456, 475, 489, plus fixture-helpers)
- `SingleThread/SingleThreadApp.swift` — `--seed` and `--ui-testing` paths + default
- `SingleThreadWatch/SingleThreadWatchApp.swift` — `--ui-testing` path + default
- `SingleThread/ContentView.swift` — 2 preview inits (:24, 39)
- `SingleThreadWatch/WatchReminderView.swift` — 1 preview init (:22)
- `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift` — 2 call sites (:19, 42) — verify defaults still work
- Fixture helpers in `ReminderStoreTests.swift` (:515–528), `BackgroundCardTests.swift` (:128), `ActionButtonTests.swift` (:95, 113), `ReminderSkipTests.swift` (:330), `ReminderDisplayTests.swift` (:65, 97), `SkippedReminderSyncServiceTests.swift` (:513), `WatchSyncPipelineTests.swift` (:197) — add `// Construction only — never saved through EventKit` comments

**Key changes**:

```swift
// ReminderStore.swift — single init (replaces both existing inits):
public init(
    eventStore: any EventKitStoring = EKEventStore(),
    skipStore: SkippedReminderStore = SkippedReminderStore(),
    excludeStore: ExcludedListStore = ExcludedListStore(),
    loadsReminders: Bool = true,
    reminders: [EKReminder] = [],
    skippedIDs: Set<String> = [],
    authorizationStatus: EKAuthorizationStatus = .notDetermined,
    excludedListTitles: Set<String> = [],
    hasHidden: Bool = false)
```

**Mechanical call-site transformations** (only the patterns, not every line):

| Before (pre-populate init) | After (merged init) |
|---|---|
| `ReminderStore(loadsReminders: false)` | `ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)` |
| `ReminderStore(loadsReminders: false, reminders: r, skippedIDs: s, authorizationStatus: a, excludedListTitles: e)` | `ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false, reminders: r, skippedIDs: s, authorizationStatus: a, excludedListTitles: e)` |
| `ReminderStore(loadsReminders: false, reminders: r, skippedIDs: s, authorizationStatus: a, excludedListTitles: e, hasHidden: h)` | Same, plus `eventStore: InMemoryEventStore()` |

**`--ui-testing` app-seam changes** (both iOS and watch):

```swift
// Before (iOS SingleThreadApp.swift:139–149):
let eventStore = EKEventStore()
let reminder = EKReminder(eventStore: eventStore)
reminder.title = "Buy groceries"
// ...
return (ReminderStore(loadsReminders: false, reminders: [reminder], ...), false)

// After:
let scratchStore = EKEventStore()
let calendar = EKCalendar(for: .reminder, eventStore: scratchStore)
let reminder = EKReminder(eventStore: scratchStore)
reminder.title = "Buy groceries"
// ...
let inMemoryStore = InMemoryEventStore(reminders: [reminder], calendars: [calendar], defaultCalendar: calendar)
return (ReminderStore(eventStore: inMemoryStore, loadsReminders: false), false)
```

The watch `--ui-testing` path (`SingleThreadWatchApp.swift:98–135`) follows the
same pattern: real `EKEventStore` for fixture construction only →
`InMemoryEventStore(reminders:calendars:defaultCalendar:)` → merged init with
`eventStore: inMemoryStore`. The `--ui-testing-excluded-list` and
`--ui-testing-live-excluded` flags still drive `excludedListTitles` via the
merged init's parameter.

**Verify**:
```bash
./scripts/test.sh
```
Then manually confirm Reminders app shows zero new entries from the test run
(when host holds `.fullAccess`).

---

## Phase 3: Final audit & verification gate

**What it delivers**: A grep-and-test gate confirming the pollution path is
fully closed. Construction-only fixture helpers are annotated.

**Files**: none modified (audit-only); fixture-helper comments from Phase 2
are rechecked.

**Key checks**:

1. **No remaining pre-populate patterns**:
   ```bash
   rg 'ReminderStore\(loadsReminders:\s*false' --no-heading | grep -v 'eventStore:'
   ```
   Every match passes `eventStore: InMemoryEventStore()` or `eventStore: fake`.

2. **No test-driven real `EKEventStore()` save paths**:
   ```bash
   rg 'EKEventStore\(\)' SingleThreadTests/ --no-heading
   ```
   Every match is either fixture construction (`EKReminder(eventStore:)`,
   `EKCalendar(for:eventStore:)`) or `makeReminderSetsDefaultCalendar`.

3. **All unit + UI tests pass**:
   ```bash
   ./scripts/test.sh
   ```

4. **Manual smoke check**: run the full gate with host holding `.fullAccess` to
   Reminders; confirm Reminders app has zero "Test reminder" entries afterward.

**Verify**:
```bash
./scripts/test.sh
```
passes cleanly, and the Reminders app shows no test-created entries.

---

## Testing Checkpoints

| After Phase | What should be true |
|---|---|
| **1** | `InMemoryEventStore.makeReminder` uses `defaultCalendar ?? calendars.first`; five of six `MakeReminderTests` run against `InMemoryEventStore` |
| **2** | `grep -c 'public init(' ReminderStore.swift` → `1`; `./scripts/test.sh` passes; no "Test reminder" entries in real Reminders |
| **3** | Audit greps produce only allowed matches; fixture helpers have `// Construction only` comments; `./scripts/test.sh` is green |