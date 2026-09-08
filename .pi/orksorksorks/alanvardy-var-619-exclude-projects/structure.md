# Structure Outline

## Approach

Add a stateless "Excluded Projects" multi-select to `SettingsView` backed by a new
`ExcludedProjectStore` (UserDefaults, mirroring `SkippedReminderStore`), filter it out in
`ReminderStore.visibleReminders`, and reuse that computed property so phone, widget, and
watch inherit the exclusion for free — with WatchConnectivity carrying the title set.

---

## Phase 1: Core exclusion state + filtering

Delivers the domain foundation every later phase builds on: a persisted, write-through set
of excluded project titles owned by `ReminderStore`, and the `visibleReminders` filter that
hides reminders whose calendar title is excluded. No UI yet, but the filter is fully real
and unit-tested — widget and watch filtering falls out immediately once a title lands in
the set.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ExcludedProjectStore.swift` (new),
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadTests/ExcludedProjectStoreTests.swift` (new), `SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
- `struct ExcludedProjectStore { init(defaults: UserDefaults = AppGroup.defaults, key: String = "excludedProjectTitles"); func load() -> [String]; func save(_ titles: [String]) }` — new, mirrors `SkippedReminderStore` (`ReminderSkip.swift:111-133`).
- `ReminderStore.excludedProjectTitles: public private(set) Set<String>` — new state, sibling of `skippedIDs`.
- `ReminderStore.onExcludedProjectsChanged: (([String]) -> Void)?` — new hook, mirroring `onSkipSetChanged`.
- `func setExcludedProjectTitles(_ titles: Set<String>)` — write-through: `excludeStore.save(...)`, fire `onExcludedProjectsChanged` + `onRemindersChanged`. No settle delay (unlike skip).
- `visibleReminders` gains `.filter { !excludedProjectTitles.contains($0.calendar?.title ?? "") }` — nil calendar always shown.
- Production init gains `excludeStore: ExcludedProjectStore = ExcludedProjectStore()`; preview/test init gains `excludedProjectTitles: Set<String>`.
- `reload()` adds `excludedProjectTitles = Set(excludeStore.load())` in the non-clear branch (load-on-reload like skip, but **no pruning** — orphaned titles linger harmlessly per design decision 1).

**Verify**: `make test` (i.e. `./scripts/test.sh --unit-only`) passes. New tests: store
load/save round-trip + UUID-keyed isolation; `visibleReminders` excludes by title, keeps
nil-calendar reminders, and is empty when all projects excluded.

---

## Phase 2: Project enumeration via the EventKit seam

Adds the read the settings UI needs: `ReminderStore.availableProjects` (sorted, deduplicated
titles) populated during `reload()` from a new `EventKitStoring.calendars(for:)` requirement.
No production caller yet, fully testable through `FakeEventStore`.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadTests/EventKitStoringTests.swift`, `SingleThreadTests/ReminderStoreTests.swift`

**Key changes**:
- `protocol EventKitStoring` adds `func calendars(for entityType: EKEntityType) -> [EKCalendar]`.
- `extension EKEventStore: EventKitStoring` adds that method (delegates to `self.calendars(for:)`).
- `ReminderStore.availableProjects: public private(set) [String]` — new; in `reload()`: `Set(eventStore.calendars(for: .reminder).map(\.title).filter { !$0.isEmpty }).sorted()`.
- `FakeEventStore` (test) gains `var returnedCalendars: [EKCalendar] = []` config + a `calendarFetchCallCount` recording; conforms to the new requirement.

**Verify**: `make test` passes. New tests: fake returns duplicate/unsorted titles →
`availableProjects` is sorted + deduped; empty calendar list yields `[]`; `reload()` sets it.

---

## Phase 3: Settings UI (phone end-to-end)

First user-visible slice: a "Projects" section with one toggle per available list; toggling
writes through `setExcludedProjectTitles`, which hides the reminder on the phone and the
widget (write-through fires `onRemindersChanged` → widget timeline reload, and the widget
already reads `visibleReminders`).

**Files**: `SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`,
`SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `SettingsView` init (both `#if os(iOS)` 4→6-arg and `#else` 3→5-arg) gains
  `excludedProjects: Binding<Set<String>>` and `availableProjects: [String]`; new
  `@Binding private var excludedProjects`; new `Section("Excluded Projects") { ForEach(availableProjects, id: \.self) { Toggle(...) } }`.
- `ContentView` passes `availableProjects: store.availableProjects` and a
  `Binding<Set<String>> { store.excludedProjectTitles } set: { store.setExcludedProjectTitles($0) }` (backed by the `@Observable` store, not `@AppStorage`).
- `ContentView` preview init forwards `excludedProjectTitles`; previews gain excluded cases.
- `SettingsViewTests` init calls add `.constant([])` / `availableProjects`; assert `"Excluded Projects"` present in `String(describing: view.body)`.

**Verify**: `make test` passes; `make build` compiles both platform initializers. Manual:
run in `iPhone 17` simulator, open Settings, toggle a project off → its next reminder
disappears from the single-thread view immediately; relaunch → exclusion persists.

---

## Phase 4: Phone↔watch sync

Extends `SkippedReminderSyncService` to carry the excluded-title set alongside the skip
set, so the watch (read-only EventKit, no App Group) learns exclusions and filters its own
`visibleReminders` locally.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`,
`SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `SkippedReminderSyncService.init` gains `excludeStore: ExcludedProjectStore = ExcludedProjectStore()`.
- `func pushExcludedProjectTitles(_ titles: [String])` — `updateApplicationContext([.excludedProjectTitles: titles])`.
- `PayloadKey` adds `static let excludedProjectTitles = "excludedProjectTitles"`.
- `didReceiveApplicationContext` reads **both** keys independently (restructure the current
  early-return so a payload carrying only excluded titles still saves) → `excludeStore.save(received)`.
- Phone + watch app entries wire `store.onExcludedProjectsChanged = { service.pushExcludedProjectTitles($0) }` (same places as `onSkipSetChanged`, `SingleThreadApp.swift:34` / `SingleThreadWatchApp.swift:19`).

**Verify**: `make test` passes. New `FakeSession` tests mirror skip: push puts
`excludedProjectTitles` in the context; receive replaces local store; missing key is a no-op.
Manual: exclude a project on phone → watch hides it after WatchConnectivity delivers; widget
with all projects excluded shows `.allDone`, not a crash.

---

## Testing Checkpoints

- **After Phase 1** — `ExcludedProjectStoreTests` + `ReminderStoreTests` filter cases green; `excludedProjectTitles`/`setExcludedProjectTitles`/`onExcludedProjectsChanged` exist; `visibleReminders` excludes by title.
- **After Phase 2** — `EventKitStoring` has `calendars(for:)`; `availableProjects` is sorted/deduped and set in `reload()`; `FakeEventStore.returnedCalendars` works.
- **After Phase 3** — Settings shows "Excluded Projects" with a toggle per project; toggling hides a reminder on phone + widget; persists across relaunch.
- **After Phase 4** — Exclusions flow phone→watch; watch filters locally; all-hooks-before-`activate()` invariant preserved.
- **Final** — `./scripts/test.sh` green (format + lint(strict) + build + Periphery + unit + UI/accessibility).

## Notes

- **Not sliceable vertically**: nothing — every slice crosses state→surface layers. Enumeration
  and persistence are separated (Phases 1–2) only because the settings UI needs both as inputs;
  each is independently green and the feature is still filter-complete after Phase 1.
- **Open/known risks** (unchanged from design): duplicate titles collapse into one toggle;
  renames orphan a harmless stale title (no cleanup); device-local lists won't sync match; nil
  `calendar` reminders always shown; `availableProjects` may be empty if Settings opens before
  first `reload()`.