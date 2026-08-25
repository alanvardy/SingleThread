# Implementation Plan

## Overview

Merge `ReminderStore`'s two inits into one injectable init, fix `InMemoryEventStore.makeReminder` calendar fidelity, and back every test call site with `InMemoryEventStore` so no test can persist to a real Apple Reminders database.

---

## Phase 1: `InMemoryEventStore` calendar fidelity

### Changes

#### 1. Add `defaultCalendar:` parameter to `InMemoryEventStore.init` and wire into `makeReminder`
**File**: `SingleThreadCore/Sources/SingleThreadCore/InMemoryEventStore.swift`
**Action**: modify

Change the init signature and store the parameter:

```swift
// Before (line 20-25):
    public init(
        reminders: [EKReminder] = [],
        calendars: [EKCalendar] = [],
        deliverCompletionOffMain: Bool = false) {

// After:
    public init(
        reminders: [EKReminder] = [],
        calendars: [EKCalendar] = [],
        deliverCompletionOffMain: Bool = false,
        defaultCalendar: EKCalendar? = nil) {
```

Add a private property and update `makeReminder` calendar assignment:

```swift
// In the body of makeReminder (line 103), change:
            reminder.calendar = calendars.first
// to:
            reminder.calendar = defaultCalendar ?? calendars.first
```

Add the private property alongside the existing `private let calendars`:

```swift
    // MARK: Private

    private let calendars: [EKCalendar]
    private let defaultCalendar: EKCalendar?
    private let deliverCompletionOffMain: Bool
```

#### 2. Switch five `MakeReminderTests` from real `EKEventStore` to `InMemoryEventStore`
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Five tests at lines 443–491 (end of `makeReminderSetsRecurrenceRule`) each call `(EKEventStore() as any EventKitStoring).makeReminder(...)`. Replace with `InMemoryEventStore().makeReminder(...)`:

- `makeReminderSetsTitle` (line 444)
- `makeReminderSetsNotes` (line 454)
- `makeReminderSetsDueDate` (line 465)
- `makeReminderLeavesUnsetFieldsNil` (line 477)
- `makeReminderSetsRecurrenceRule` (line 490)

Pattern (applied five times):
```swift
// Before:
let reminder = (EKEventStore() as any EventKitStoring).makeReminder(...)
// After:
let reminder = InMemoryEventStore().makeReminder(...)
```

#### 3. Add new test `makeReminderUsesDefaultCalendar`
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Insert before `makeReminderSetsDefaultCalendar` (line 502):

```swift
@Test
func makeReminderUsesDefaultCalendar() {
    let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
    calendar.title = "Custom"
    let store = InMemoryEventStore(calendars: [], defaultCalendar: calendar)
    let reminder = store.makeReminder(
        title: "Test",
        notes: nil,
        dueDate: nil,
        recurrenceRule: nil)
    #expect(reminder.calendar == calendar)
}
```

#### 4. Annotate `makeReminderSetsDefaultCalendar` as intentionally real-store
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Add a comment above `makeReminderSetsDefaultCalendar` (line 502):
```swift
// Tests real EventKit calendar behavior — intentionally uses EKEventStore.
@Test
func makeReminderSetsDefaultCalendar() {
```

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/ReminderStoreTests/MakeReminderTests` passes (all 7 tests)
- [x] `grep -c 'EKEventStore() as any EventKitStoring).makeReminder' SingleThreadTests/ReminderStoreTests.swift` → only real-store test remains. NOTE: count is `0` not `1` because `makeReminderSetsDefaultCalendar` uses a local variable `(eventStore as any EventKitStoring)` rather than inline `EKEventStore()` — the plan's literal pattern never matched even before changes. Intent (only `makeReminderSetsDefaultCalendar` uses a real store) is satisfied: `grep -c '(eventStore as any EventKitStoring).makeReminder'` → `1`.

#### Manual
- [ ] None needed for this phase.

---

## Phase 2: Single `ReminderStore` init + all call sites

### Changes

#### 1. Merge two inits into one
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

Delete both existing inits (lines 13-39) and replace with a single init:

```swift
    /// Single init. Production callers accept all defaults; tests inject
    /// an in-memory event store and pre-seeded state.
    public init(
        eventStore: any EventKitStoring = EKEventStore(),
        skipStore: SkippedReminderStore = SkippedReminderStore(),
        excludeStore: ExcludedListStore = ExcludedListStore(),
        loadsReminders: Bool = true,
        reminders: [EKReminder] = [],
        skippedIDs: Set<String> = [],
        authorizationStatus: EKAuthorizationStatus = .notDetermined,
        excludedListTitles: Set<String> = [],
        hasHidden: Bool = false) {
        self.eventStore = eventStore
        self.skipStore = skipStore
        self.excludeStore = excludeStore
        self.loadsReminders = loadsReminders
        self.reminders = reminders
        self.skippedIDs = skippedIDs
        self.authorizationStatus = authorizationStatus
        self.excludedListTitles = excludedListTitles
        self.hasHidden = hasHidden
    }
```

#### 2. Update `ReminderStoreTests.swift` call sites (~17)
**File**: `SingleThreadTests/ReminderStoreTests.swift`
**Action**: modify

Every `ReminderStore(` call site using the pre-populate init (no `eventStore:` parameter) gets `eventStore: InMemoryEventStore()` prepended. The pattern is mechanical:

```swift
// Before:
let store = ReminderStore(
    loadsReminders: false,
    reminders: [rem, other],
    skippedIDs: [rem.calendarItemIdentifier],
    authorizationStatus: .fullAccess)

// After:
let store = ReminderStore(
    eventStore: InMemoryEventStore(),
    loadsReminders: false,
    reminders: [rem, other],
    skippedIDs: [rem.calendarItemIdentifier],
    authorizationStatus: .fullAccess)
```

Affected lines (each gets `eventStore: InMemoryEventStore()` as the first argument):
- Lines 14, 27, 37, 49, 65, 78, 90, 102, 115, 129, 147, 176, 189, 205, 222, 237, 245, 257, 272, 284, 299, 315, 327, 339, 353

Lines already using `eventStore:` (367-368: `eventStore: fake, loadsReminders: true` — already correct) need no change.

Lines 375, 381, 388, 395: `ReminderStore(loadsReminders: false)` — these get `eventStore: InMemoryEventStore()` prepended.

Line 404 and 414: same pre-populate pattern — add `eventStore: InMemoryEventStore()`.

#### 3. Update `ActionButtonTests.swift` (3 call sites)
**File**: `SingleThreadTests/ActionButtonTests.swift`
**Action**: modify

Three call sites at lines 79, 98, 117. Each uses the pre-populate init. Add `eventStore: InMemoryEventStore()`:

- Line 79 (`storeWithReminder()` helper — line 117): add `eventStore: InMemoryEventStore(),`
- Line 98 (`buttonsHiddenWhenNoVisibleReminder`): add `eventStore: InMemoryEventStore(),`
- The `EKEventStore()` at line 95 inside `buttonsHiddenWhenAllSkipped` for reminder construction stays (fixture construction).

#### 4. Update `ReminderDictationTests.swift` (1 call site)
**File**: `SingleThreadTests/ReminderDictationTests.swift`
**Action**: modify

Line 176: `let store = ReminderStore(loadsReminders: false)` → `let store = ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false)`

#### 5. Update `BackgroundCardTests.swift` (1 call site)
**File**: `SingleThreadTests/BackgroundCardTests.swift`
**Action**: modify

Line 131 (inside `storeWithReminder()`): add `eventStore: InMemoryEventStore(),`

#### 6. Update `UITestingSeedTests.swift` (1 call site)
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

Line 53 already uses `eventStore: InMemoryEventStore(reminders: seed.reminders, calendars: seed.calendars)`. No change needed — verify it compiles with the merged init (it should, same parameter names).

#### 7. Update `EventKitStoringTests.swift` (3 call sites)
**File**: `SingleThreadTests/EventKitStoringTests.swift`
**Action**: modify

Lines 251, 399, 467 already use `eventStore: fake` / `eventStore: eventStore`. No change needed — verify they compile.

#### 8. Update `SkippedReminderSyncServiceTests.swift` (1 call site)
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify

Line 400-407 uses the pre-populate init:

```swift
let store = ReminderStore(
    loadsReminders: false,
    reminders: [
        inListReminder(title: "A", list: "Work"),
        inListReminder(title: "B", list: "Personal")
    ],
    skippedIDs: [],
    authorizationStatus: .fullAccess)
```

Add `eventStore: InMemoryEventStore(),` as the first parameter.

#### 9. Update `--seed` path in `SingleThreadApp.swift`
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Lines 119-121: pass `defaultCalendar: seed.calendars.first` to `InMemoryEventStore` init so `makeReminder` (invoked via `addReminder`) uses the correct calendar:

```swift
// Before (lines 119-121):
let inMemoryStore = InMemoryEventStore(
    reminders: seed.reminders,
    calendars: seed.calendars)

// After:
let inMemoryStore = InMemoryEventStore(
    reminders: seed.reminders,
    calendars: seed.calendars,
    defaultCalendar: seed.calendars.first)
```

The `ReminderStore(eventStore: inMemoryStore, loadsReminders: true)` call on line 122-124 already uses the production-init parameter name and works unchanged.

#### 10. Update `--ui-testing` path in `SingleThreadApp.swift`
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Lines 137-150: switch from pre-populate init to `InMemoryEventStore`-backed init. Use the real `EKEventStore` only for fixture construction:

```swift
// Before (lines 139-150):
if arguments.contains("--ui-testing") {
    UserDefaults.standard.set(true, forKey: "enableActionButtons")
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.notes = "Don't forget the milk"
    return (ReminderStore(
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess), false)
}

// After:
if arguments.contains("--ui-testing") {
    UserDefaults.standard.set(true, forKey: "enableActionButtons")
    let scratchStore = EKEventStore()
    let reminder = EKReminder(eventStore: scratchStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.notes = "Don't forget the milk"
    let inMemoryStore = InMemoryEventStore(
        reminders: [reminder],
        calendars: [])
    return (ReminderStore(
        eventStore: inMemoryStore,
        loadsReminders: false), false)
}
```

The default path at line 153 (`return (ReminderStore(loadsReminders: loads), false)`) stays unchanged — it uses the production init with defaults.

#### 11. Update `SingleThreadWatchApp.swift` (2 call sites)
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

**Line 16**: `ReminderStore(loadsReminders: true)` — uses the production init with defaults, no change needed.

**`uiTestingStore` method (lines 98-135)**: switch from pre-populate init to `InMemoryEventStore`-backed init. The `EKEventStore()` is renamed to `scratchStore` and used only for fixture construction. The merged init receives both `eventStore: inMemoryStore` (injecting the fake) and the existing seeding parameters (`reminders:`, `skippedIDs:`, `authorizationStatus:`, `excludedListTitles:`):

```swift
// Before:
private static func uiTestingStore(arguments: [String]) -> ReminderStore {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.notes = "Don't forget the milk"
    for flag in ["--ui-testing-excluded-list", "--ui-testing-live-excluded"] {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { continue }
        let list = arguments[index + 1]
        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = list
        reminder.calendar = calendar
        return ReminderStore(
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: flag == "--ui-testing-excluded-list" ? [list] : [])
    }
    return ReminderStore(
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}

// After:
private static func uiTestingStore(arguments: [String]) -> ReminderStore {
    let scratchStore = EKEventStore()
    let reminder = EKReminder(eventStore: scratchStore)
    reminder.title = "Buy groceries"
    reminder.priority = 5
    reminder.notes = "Don't forget the milk"
    for flag in ["--ui-testing-excluded-list", "--ui-testing-live-excluded"] {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count else { continue }
        let list = arguments[index + 1]
        let calendar = EKCalendar(for: .reminder, eventStore: scratchStore)
        calendar.title = list
        reminder.calendar = calendar
        let inMemoryStore = InMemoryEventStore(reminders: [reminder])
        return ReminderStore(
            eventStore: inMemoryStore,
            loadsReminders: false,
            reminders: [reminder],
            skippedIDs: [],
            authorizationStatus: .fullAccess,
            excludedListTitles: flag == "--ui-testing-excluded-list" ? [list] : [])
    }
    let inMemoryStore = InMemoryEventStore(reminders: [reminder])
    return ReminderStore(
        eventStore: inMemoryStore,
        loadsReminders: false,
        reminders: [reminder],
        skippedIDs: [],
        authorizationStatus: .fullAccess)
}
```

#### 12. Update `ContentView.swift` preview inits (2 call sites)
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Line 24** (production-focused preview init): `store = ReminderStore(loadsReminders: loadsReminders)` → stays unchanged (uses production init with defaults).

**Lines 38-45** (pre-populate preview init): add `eventStore: InMemoryEventStore()`:

```swift
// Before:
store = ReminderStore(
    loadsReminders: loadsReminders,
    reminders: reminders,
    skippedIDs: skippedIDs,
    authorizationStatus: authorizationStatus,
    excludedListTitles: excludedListTitles,
    hasHidden: hasHidden)

// After:
store = ReminderStore(
    eventStore: InMemoryEventStore(),
    loadsReminders: loadsReminders,
    reminders: reminders,
    skippedIDs: skippedIDs,
    authorizationStatus: authorizationStatus,
    excludedListTitles: excludedListTitles,
    hasHidden: hasHidden)
```

#### 13. Update `WatchReminderView.swift` preview init (1 call site)
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify

Line 22 area: add `eventStore: InMemoryEventStore()`:

```swift
// Before:
store = ReminderStore(
    loadsReminders: loadsReminders,
    reminders: reminders,
    skippedIDs: skippedIDs,
    authorizationStatus: authorizationStatus,
    hasHidden: hasHidden)

// After:
store = ReminderStore(
    eventStore: InMemoryEventStore(),
    loadsReminders: loadsReminders,
    reminders: reminders,
    skippedIDs: skippedIDs,
    authorizationStatus: authorizationStatus,
    hasHidden: hasHidden)
```

#### 14. Verify `ReminderIntents.swift` (2 call sites) — no changes needed
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`
**Action**: verify (no modification)

Lines 19 and 42: `ReminderStore(loadsReminders: true)` — uses the production init with only `loadsReminders` overridden. The merged init's default `eventStore: EKEventStore()` matches current behavior. No change.

#### 15. Annotate fixture helpers with `// Construction only — never saved through EventKit`
**Files**: multiple
**Action**: modify (comments only)

Add a comment above each fixture helper that constructs `EKReminder`/`EKCalendar` with a real `EKEventStore()`:

- `SingleThreadTests/ReminderStoreTests.swift`: above `makeReminder(title:priority:dateComponents:)` (line 515) and `makeReminder(title:calendarTitle:)` (line 524)
- `SingleThreadTests/BackgroundCardTests.swift`: above `storeWithReminder()` (line 127)
- `SingleThreadTests/ActionButtonTests.swift`: above `storeWithReminder()` (line 113) and inside `buttonsHiddenWhenAllSkipped` (line 95)
- `SingleThreadTests/ReminderSkipTests.swift`: above `makeReminder(title:priority:dateComponents:)` (line 328)
- `SingleThreadTests/ReminderDisplayTests.swift`: above the inline `EKEventStore()` at line 65 (inside `mapsListNameFromCalendarTitle`) and above `makeReminder(title:)` at line 96
- `SingleThreadTests/EventKitStoringTests.swift`: above `makeReminder(title:)` (line ~455) and `makeCalendar(title:)` (line ~460)
- `SingleThreadTests/SkippedReminderSyncServiceTests.swift`: above `inListReminder(title:list:)` (line 513)
- `SingleThreadWatchTests/WatchSyncPipelineTests.swift`: above `inListReminder(title:list:)` (line 197)

Comment format:
```swift
// Construction only — never saved through EventKit.
```

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes on iPhone 17 simulator
- [ ] `grep -c 'public init(' SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift` → `1`
- [ ] `rg 'EKEventStore\(\)' SingleThreadTests/ --no-heading` — every match is either fixture construction (`EKReminder(eventStore:)`, `EKCalendar(for:eventStore:)`) or `makeReminderSetsDefaultCalendar`
- [ ] `rg 'ReminderStore\(loadsReminders:\s*false' --no-heading | grep -v 'eventStore:'` returns empty (no remaning pre-populate-init call sites without eventStore injection)

#### Manual
- [ ] Run `./scripts/test.sh` with host holding `.fullAccess` to Reminders; confirm Reminders app has zero "Test reminder" / "Buy milk" / "Buy groceries" entries afterward

---

## Phase 3: Final audit & verification gate

### Changes

No file modifications. Audit-only phase rechecking the comments and grep gates from Phase 2.

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes cleanly on iPhone 17 simulator
- [ ] `rg 'EKEventStore\(\)' SingleThreadTests/ --no-heading` — output manually reviewed: every match is either fixture construction (`EKReminder(eventStore:)`, `EKCalendar(for:eventStore:)`) or the intentionally real `makeReminderSetsDefaultCalendar` test
- [ ] `rg 'ReminderStore\(loadsReminders:\s*false' --no-heading | grep -v 'eventStore:'` — empty output (zero remaining pre-populate init patterns without injection)
- [ ] `rg '// Construction only — never saved through EventKit' --no-heading` — matches ≥ 10 fixture helpers across the test files listed in Phase 2 step 15

#### Manual
- [ ] Run `./scripts/test.sh` with host holding `.fullAccess` to Reminders; confirm Reminders app shows zero test-created entries

---

## Testing Checkpoints

| After Phase | What should be true |
|---|---|
| **1** | `InMemoryEventStore.makeReminder` uses `defaultCalendar ?? calendars.first`; five of six `MakeReminderTests` run against `InMemoryEventStore`; new `makeReminderUsesDefaultCalendar` passes |
| **2** | `grep -c 'public init(' ReminderStore.swift` → `1`; `./scripts/test.sh` passes; no "Test reminder" entries in real Reminders after test run |
| **3** | Audit greps produce only allowed matches; fixture helpers have `// Construction only` comments; `./scripts/test.sh` is green |