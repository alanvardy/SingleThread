# Implementation Plan

## Overview

Rename "project" → "list" across every layer of the exclusion feature (Swift symbols,
file names, App Group UserDefaults key, WatchConnectivity payload key, UI-test seed
key/launch arg, user-facing copy), then fix two behavior defects: the exclusions push
clobbering other application-context keys, and dead watch-side push wiring.

Verification commands used throughout:
- Full gate: `./scripts/test.sh`
- Unit tests only: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`
- Sync suite: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests`
- Dead code: `make periphery`

---

## Phase 1: Symbol & File Rename (no string changes)

Pure mechanical symbol + file rename. **Every quoted string literal stays untouched**
in this phase — including `"excludedProjectTitles"`, `"excludedProjects"`,
`"--ui-testing-excluded"`, and `"Excluded Projects"`. Behavior is byte-for-byte
identical afterward.

### Changes

#### 1. Rename `ExcludedProjectStore.swift` file and type
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift`
**Action**: modify + `git mv` to `ExcludedListStore.swift`

```bash
git mv SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift \
       SingleThreadCore/Sources/SingleThreadCore/ExcludedListStore.swift
```

```swift
/// Persists the excluded-list titles in UserDefaults.
public struct ExcludedListStore {
    // init params unchanged — key literal stays "excludedProjectTitles" until Phase 2
    public init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedProjectTitles") { ... }
}
```

#### 2. `ReminderStore` symbols
**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`
**Action**: modify

| Old | New |
|---|---|
| `excludeStore: ExcludedProjectStore = ExcludedProjectStore()` (both inits) | `ExcludedListStore()` |
| preview/test init param `excludedProjectTitles:` | `excludedListTitles:` |
| `public private(set) var excludedProjectTitles: Set<String>` | `excludedListTitles` |
| `public private(set) var availableProjects: [String]` | `availableLists` |
| `setExcludedProjectTitles(_:)` | `setExcludedListTitles(_:)` |
| `refreshExcludedProjectTitles(_:)` | `refreshExcludedListTitles(_:)` |
| `onExcludedProjectsChanged` | `onExcludedListsChanged` |
| `private let excludeStore: ExcludedProjectStore` | `ExcludedListStore` |

Update doc comments on these declarations ("excluded-project mutation" →
"excluded-list mutation", etc.). `visibleReminders` filter line becomes
`.filter { !excludedListTitles.contains($0.calendar?.title ?? "") }`; the reload path
becomes `excludedListTitles = Set(excludeStore.load())`.

#### 3. `SkippedReminderSyncService` symbols (key literal unchanged)
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

```swift
// init param type only:
excludeStore: ExcludedListStore = ExcludedListStore(),

// hook rename (declaration ~:78):
public nonisolated(unsafe) var onExcludedListTitlesReceived: (([String]) -> Void)?

// method rename (~:107) — body unchanged this phase:
public func pushExcludedListTitles(_ titles: [String]) {
    do {
        try session.updateApplicationContext([PayloadKey.excludedProjectTitles: titles])  // literal unchanged until Phase 2
    } catch { ... }
}

// PayloadKey case rename, raw value UNCHANGED this phase (~:236):
static let excludedListTitles = "excludedProjectTitles"

// receive path (~:183-186): use PayloadKey.excludedListTitles / onExcludedListTitlesReceived
```

#### 4. Seed seam properties (JSON key preserved via explicit CodingKeys)
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

⚠️ `SeedPayload` currently uses *synthesized* `CodingKeys` from property names.
Renaming the property would silently change the decoded JSON key, violating the
"no string changes" rule. Add an **explicit** `CodingKeys` enum now:

```swift
var reminders: [ReminderSeed]
var calendars: [String] = []
var excludedLists: [String] = []   // was excludedProjects

private enum CodingKeys: String, CodingKey {
    case reminders, calendars
    case excludedLists = "excludedProjects"   // literal preserved; changed to "excludedLists" in Phase 3
}

func materialize() -> UITestingSeed {
    ...
    return UITestingSeed(
        reminders: createdReminders,
        calendars: createdCalendars,
        excludedListTitles: Set(excludedLists))
}
```

Rename `UITestingSeed.excludedProjectTitles: Set<String>` → `excludedListTitles`.
The `persistedKeys` literal `"excludedProjectTitles"` (:54) stays as-is until Phase 2.

#### 5. iOS app layer
**Files**: `SingleThread/SingleThreadApp.swift`, `SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`
**Action**: modify

- `SingleThreadApp.swift`: `service.onExcludedListTitlesReceived = { store?.refreshExcludedListTitles(...) }` (:45-46); `store.onExcludedListsChanged = { service.pushExcludedListTitles(titles) }` (:56); seed path `store.setExcludedListTitles(seed.excludedListTitles)` (:122-123).
- `ContentView.swift`: `excludedProjectsBinding` → `excludedListsBinding` (`get: { store.excludedListTitles }`, `set: { store.setExcludedListTitles($0) }`, :233-238); `SettingsView` call sites pass `excludedLists:` / `availableLists:` labels (:142-143, :155-156); preview mock `mockReminderInProject` → `mockReminderInList` (:572); `#Preview("All Excluded")` passes `excludedListTitles: ["Groceries"]` (:610-620).
- `SettingsView.swift`: rename view `ExcludedProjectsView` → `ExcludedListsView`; both `init`s take `excludedLists: Binding<Set<String>>`, `availableLists: [String]`; stored props renamed; `excludedBinding(for:)` internals use `list` local naming; `NavigationLink` target/call-site labels updated. **Strings stay**: footer `"Excluded projects are hidden from the reminder list."`, title `"Excluded Projects"`, `Label("Excluded Projects", ...)`.

#### 6. Watch app layer
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify

- Receive hook: `service.onExcludedListTitlesReceived = { store?.refreshExcludedListTitles(Set(titles)) }` (:41-43).
- Push wiring at :48 (`store.onExcludedProjectsChanged = ...`) is **renamed only** this phase (`onExcludedListsChanged` / `pushExcludedListTitles`) — it is deleted in Phase 5.
- `uiTestingStore`: local `let project = ...` → `let list`; comment updated to say "list"; launch-arg literal `"--ui-testing-excluded"` stays until Phase 3; init arg becomes `excludedListTitles: [list]`.

#### 7. Test renames
**Files & actions**:

- `git mv SingleThreadTests/ExcludedProjectStoreTests.swift SingleThreadTests/ExcludedListStoreTests.swift`; struct → `ExcludedListStoreTests`; all `ExcludedProjectStore(...)` constructions → `ExcludedListStore(...)` (string keys like `"test-excluded-roundtrip-…"` are arbitrary test keys, not the production key — leave them).
- `SingleThreadTests/ReminderStoreTests.swift`: `visibleRemindersFiltersOutExcludedProjectTitles` → `…ExcludedListTitles` (:75); init args `excludedProjectTitles:` → `excludedListTitles:` (:83, :95, :107); MARK `availableProjects` → `availableLists` (:111); `availableProjectsDefaultsToEmpty` → `availableListsDefaultsToEmpty` (:114), assertion `store.availableLists.isEmpty` (:120); `setExcludedProjectTitlesPersistsAndFiresHooks` → `setExcludedListTitlesPersistsAndFiresHooks` (:126); `ExcludedProjectStore(` → `ExcludedListStore(` (:128); `onExcludedProjectsChanged` → `onExcludedListsChanged` (:132); `store.setExcludedListTitles(["Work", "Personal"])` (:135); `#expect(store.excludedListTitles == …)` (:137); `refreshExcludedProjectTitlesUpdatesSetAndFiresRemindersChangedOnly` → `refreshExcludedListTitles…` (:146), body likewise (:155, :157, :159).
- `SingleThreadTests/EventKitStoringTests.swift`: struct `ReminderStoreAvailableProjectsTests` → `ReminderStoreAvailableListsTests` (:417); `availableProjectsSortedAndDeduplicatedAfterReload` → `availableListsSorted…` (:419), assert `store.availableLists == ["Personal", "Work", "work"]` (:432); `availableProjectsEmptyWhenNoCalendars` → `availableListsEmptyWhenNoCalendars` (:437, :443).
- `SingleThreadTests/SkippedReminderSyncServiceTests.swift`: helper `inProjectReminder(title:project:)` → `inListReminder(title:list:)` (:477) and its two call sites (:361-362); `pushExcludedProjectTitlesUpdatesApplicationContext` → `pushExcludedListTitlesUpdatesApplicationContext` (:310); `service.pushExcludedListTitles(["Work", "Home"])` (:316); hook wiring `onExcludedListTitlesReceived` (:371); MARK comments → list terminology (:307). **Dictionary literals stay** `"excludedProjectTitles"` until Phase 2.
- `SingleThreadTests/UITestingSeedTests.swift`: `parsesCalendarsAndExcludedProjects` → `parsesCalendarsAndExcludedLists` (:27); assertion `seed?.excludedListTitles == ["Work"]` (:35). The JSON literal keeps `"excludedProjects"` until Phase 3.
- `SingleThreadTests/SettingsViewTests.swift`: call-site labels `excludedLists: .constant([])`, `availableLists: ["Work", "Personal"]` (:23-24, :36-37). The `"Excluded Projects"` body assertion (:55) stays until Phase 3.
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift`: test name `testExcludedProjectDoesNotRenderReminder` → `testExcludedListDoesNotRenderReminder` (:25); launch-arg array and comments keep old strings until Phase 3.

### Verification
#### Automated
- [x] `./scripts/test.sh` passes (all unit + UI tests, lint, Periphery) with zero test-logic edits beyond renames
- [x] `rg -in 'excludedProject|availableProjects|inProject|pushExcludedProject' --type swift` returns no hits outside quoted string literals
- [x] `git diff` review confirms no changed text inside quotes (string literals identical)

#### Manual
- [ ] Eye-review the diff for collateral damage from the mechanical rename (per design's grep-completeness mitigation)

---

## Phase 2: Persisted + Wire Key Literal Rename

Moves the App Group UserDefaults key and WC payload key to `"excludedListTitles"` in
one atomic step. Accepted cost (design Q1=B): existing users' exclusions reset once;
mixed-version pairs briefly stop syncing exclusions.

### Changes

#### 1. Store default key
**File**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedListStore.swift`
**Action**: modify

```swift
public init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedListTitles") {
```

#### 2. Wire payload key
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify

```swift
private enum PayloadKey {
    ...
    static let excludedListTitles = "excludedListTitles"   // was "excludedProjectTitles"
```

Both targets compile this enum from SingleThreadCore, so sender/receiver cannot drift.

#### 3. Seed persisted-key reset list
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

```swift
private static let persistedKeys = [
    "skippedReminderIdentifiers",
    "excludedListTitles",   // was "excludedProjectTitles"
    ...
]
```

Must move in lockstep or seeded UI-test relaunches leak state.

#### 4. Test string assertions
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify — update every raw dictionary-key literal pinning the wire format:

- `pushExcludedListTitlesUpdatesApplicationContext` (:319):
  `let titles = try #require(context["excludedListTitles"] as? [String])`
- `receiveContextReplacesLocalExcludedTitles` (:333):
  `didReceiveApplicationContext: ["excludedListTitles": ["B", "C"]]`
- `receivedExclusionRefreshFiltersVisibleReminders` (:380):
  `didReceiveApplicationContext: ["excludedListTitles": ["Work"]]`

(The `"skippedReminderIdentifiers"` literals elsewhere, e.g. :58, do not change.)

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests` passes — the string-pinning tests prove all four copies moved together
- [x] Unit portion of `./scripts/test.sh` green

#### Manual
- [ ] Launch app in Simulator, toggle an exclusion in Settings, force-quit and relaunch — exclusion persists (plist round-trip under new key)

---

## Phase 3: Seed Seam + User-Facing Copy

Renames the test-only seed surface (JSON key, launch arg) and all user-visible strings.
Zero device impact.

### Changes

#### 1. Seed JSON key
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

```swift
private enum CodingKeys: String, CodingKey {
    case reminders, calendars
    case excludedLists = "excludedLists"   // was "excludedProjects"
}
```

Also update the schema doc comment at the top of the file (:15):
`"excludedLists": ["Work"]`. (Keep the explicit `CodingKeys` enum.)

#### 2. Launch argument
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify (consumed at ~:74-89)

```swift
if let index = arguments.firstIndex(of: "--ui-testing-excluded-list"),
   index + 1 < arguments.count {
    let list = arguments[index + 1]
    ...
}
```

Update the accompanying comment mentioning `--ui-testing-excluded "<project>"`.

#### 3. User-facing copy
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

- `.navigationTitle("Excluded Lists")` (:34)
- `Label("Excluded Lists", systemImage: "eye.slash")` (:183)
- Footer: `Text("Excluded lists are hidden from the reminder list.")` (:31)

#### 4. Tests
**Files & actions**:

- `SingleThreadTests/UITestingSeedTests.swift` (:30): seed JSON literal becomes
  `#"{"reminders":[{"title":"A"}],"calendars":["Groceries","Work"],"excludedLists":["Work"]}"#`
- `SingleThreadTests/SettingsViewTests.swift` (:55):
  `#expect(bodyDescription.contains("Excluded Lists"))`
- `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows.swift` (:26-27):
  `app.launchArguments = ["--ui-testing", "--ui-testing-excluded-list", "Work"]`;
  comments in the test updated to "list" terminology.

### Verification
#### Automated
- [x] `./scripts/test.sh` passes end-to-end, including `SingleThreadWatchUITests/SingleThreadWatchUITestsFlows/testExcludedListDoesNotRenderReminder` exercising the renamed launch arg

#### Manual
- [ ] Run the iOS app, open Settings — row reads "Excluded Lists"; pushed screen's navigation title matches; footer reads "Excluded lists are hidden from the reminder list."

---

## Phase 4: Fix Application-Context Clobbering

`pushExcludedListTitles` sends a single-key context that wipes skips/sort/show-date
from the stored application context. It now re-carries `skippedReminderIdentifiers`,
mirroring `pushSortOption` (:118-128) and `pushShowDate` (:134-144).

### Changes

#### 1. Push implementation
**File**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
**Action**: modify (~:107-115)

```swift
/// Push the full excluded-list title array alongside the current skip set so
/// an exclusions-only push doesn't clobber other context keys on the counterpart.
public func pushExcludedListTitles(_ titles: [String]) {
    do {
        try session.updateApplicationContext([
            PayloadKey.skippedReminderIdentifiers: skipStore.load(),
            PayloadKey.excludedListTitles: titles
        ])
    } catch {
        let description = error.localizedDescription
        Self.logger.error("Failed to push excluded list titles: \(description, privacy: .public)")
    }
}
```

Also update the delegate comment block (~:171-177): exclusions no longer travel in a
separate single-key context.

#### 2. Test pins both keys
**File**: `SingleThreadTests/SkippedReminderSyncServiceTests.swift`
**Action**: modify `pushExcludedListTitlesUpdatesApplicationContext` (~:310-322)

```swift
@Test
func pushExcludedListTitlesUpdatesApplicationContext() throws {
    let fake = FakeSession()
    let skipStore = SkippedReminderStore(defaults: .standard, key: "test-excl-push-skip-\(UUID().uuidString)")
    let excludeStore = ExcludedListStore(defaults: .standard, key: "test-excl-push-\(UUID().uuidString)")
    let service = SkippedReminderSyncService(session: fake, skipStore: skipStore, excludeStore: excludeStore)

    service.pushExcludedListTitles(["Work", "Home"])

    let context = try #require(fake.lastContext)
    let titles = try #require(context["excludedListTitles"] as? [String])
    #expect(Set(titles) == ["Work", "Home"])
    // Re-carries the skip set so the whole-context replacement doesn't drop it.
    #expect(context["skippedReminderIdentifiers"] != nil)
}
```

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/SkippedReminderSyncServiceTests` passes, with the updated test asserting both keys present

#### Manual
- [ ] Pair phone + watch simulators, change an exclusion on the phone, confirm skips still render filtered on the watch after context re-delivery

---

## Phase 5: Remove Dead Watch Push Wiring

Nothing on watch ever calls `setExcludedListTitles`, so the watch-side push-hook
wiring is unreachable. Delete it; receive path stays intact.

### Changes

#### 1. Remove unreachable wiring
**File**: `SingleThreadWatch/SingleThreadWatchApp.swift`
**Action**: modify (~:48)

Delete:
```swift
store.onExcludedListsChanged = { titles in service.pushExcludedListTitles(titles) }
```
Replace with a documenting comment:
```swift
// Exclusions sync phone→watch only: nothing on watch edits exclusions, so no
// push hook is wired here. The receive path above applies incoming exclusions.
```

### Verification
#### Automated
- [ ] Build succeeds: `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- [ ] `make periphery` clean — proves nothing else referenced the removed closure assignment
- [ ] Final full gate before PR: `./scripts/test.sh` green (unit + UI on iPhone 17 / iPad A16, lint, Periphery)

#### Manual
- [ ] None required beyond the automated coverage (watch UI test still exercises the receive path)

---

## Testing Checkpoints
- **After Phase 1**: full gate green; diff contains no changed string literals — safe rollback point if rename review finds collateral damage.
- **After Phase 2**: persisted/wire literals aligned everywhere; string-pinning sync tests green; manual plist persistence check done.
- **After Phase 3**: user-facing copy and seed/launch-arg surface fully renamed; watch exclusion UI flow green.
- **After Phase 4**: exclusion pushes carry skips + exclusions; sync suite green.
- **After Phase 5**: no dead watch wiring; Periphery clean; final `./scripts/test.sh` gate green before PR.

## Notes on Slicing Limits
Phase 1 cannot be split further vertically: Swift symbols are coupled by compilation
across app/core/test targets, so partial renames yield non-compiling intermediates.
Phases 2–4 are genuinely independent — if Phase 4 slips, Phases 1–3 still deliver the
complete rename as a shippable unit.

## Implementation Notes (deviations & gotchas)
- **Explicit `CodingKeys` added in Phase 1**: `SeedPayload` uses synthesized coding
  keys today, so renaming the property alone would have silently changed the seed
  JSON key during the "no string changes" phase. The explicit enum pins the old key
  until Phase 3 flips it. (Structural necessity, not a design change.)
- **No migration/fallback code** anywhere, per design decision 1 — one-time reset of
  live users' exclusions is accepted.
- **Widget target**: untouched; it reads none of the renamed keys.
