# Structure Outline

## Approach

Add a "Show tasks with no date" toggle that, when ON, makes `ReminderStore.reload()`
fetch a nil/nil predicate and keep only undated or in-window reminders. The flag is
an `@AppStorage` persisted in the **App Group** so the widget can read it, and rides
the existing WatchConnectivity skip-sync path (as a combined context) to reach the
watch. Three vertical slices: phone-first, then widget, then watch.

---

## Phase 1: Phone app — toggle, fetch strategy, and persistence

Delivers the end-to-end user-visible feature on iOS/macOS: a Settings toggle that,
when flipped, makes undated reminders appear in the phone list, survive relaunch, and
revert byte-for-byte to today's behavior when off.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderDateFilter.swift`,
`SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`,
`SingleThreadTests/EventKitStoringTests.swift`, `SingleThreadTests/ReminderStoreTests.swift`,
`SingleThreadTests/SingleThreadTests.swift`
(`ReminderDateFilterTests`), `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:
- `public var showsUndatedReminders = false` — new stored property on `ReminderStore`
- `public func reload(clearSkipped: Bool = false) async` — modified: when
  `showsUndatedReminders`, build the predicate with `nil`/`nil` dates and post-filter
  `fetched` before `reminders = …`; otherwise unchanged
- `static func isInCurrentWindow(_ date: Date?, calendar: Calendar = .current, now: Date = Date()) -> Bool` — new pure helper in `ReminderDateFilter` (`nil` → true; else
  `overdueCutoff ≤ date ≤ endOfToday`)
- `@AppStorage("showUndatedReminders", store: AppGroup.defaults) private var showUndatedReminders = false` — new in `ContentView` (note `store:` differs from the
  other four prefs, which use `.standard`)
- `ContentView` `.task` sets `store.showsUndatedReminders = showUndatedReminders` before
  `store.start()`; new `.onChange(of: showUndatedReminders)` sets the store flag then
  `await store.reload()`
- `SettingsView`: new `showUndatedReminders: Binding<Bool>` init param (both the
  `#if os(iOS)` and `#else` variants) + `@Binding private var showUndatedReminders: Bool`
  + `Toggle(isOn: $showUndatedReminders) { Label("Show Undated", systemImage: "calendar.badge.minus") }`
- `FakeEventStore`: record `lastStartDate`/`lastEndDate` from
  `predicateForIncompleteReminders` (currently the args are ignored)

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests`.
New tests: `isInCurrentWindow` nil/in-window/out-of-window cases; `reload` with
`showsUndatedReminders = true` keeps undated + in-window and drops out-of-window, and
with `false` passes non-nil predicate dates; `SettingsView` body contains "Show Undated".
Manual: run app, create a no-due-date reminder, toggle ON → it appears in the list;
toggle OFF → it disappears; relaunch → the setting persists.

---

## Phase 2: Widget mirror — read the App Group flag

Makes `NextThingProvider` honor the same toggle by reading the shared App Group value
before its `reload()`. No new API — consumes the App Group persistence established in
Phase 1.

**Files**: `SingleThreadWidget/NextThingWidget.swift`

**Key changes**:
- `NextThingProvider.makeEntry() async -> NextThingEntry` — modified: after building
  the fresh `ReminderStore(loadsReminders: true)`, set
  `store.showsUndatedReminders = AppGroup.defaults.bool(forKey: "showUndatedReminders")`
  before `await store.reload()`. The existing `onRemindersChanged →
  reloadAllTimelines` path (`SingleThreadApp.swift`) already re-renders the widget.

**Verify**: `make build` (widget extension compiles) + `make lint`. Manual: toggle ON
on the phone, add an undated reminder, confirm the widget shows it (and hides it when
OFF). This phase is directly testable on the simulator and exercises the load-bearing
`@AppStorage(store: AppGroup.defaults)` choice.

---

## Phase 3: Watch mirror — combined WatchConnectivity context

Pushes the toggle phone→watch as one combined `updateApplicationContext` — not a second
payload, which would clobber the skip IDs — and receives it on the watch. Requires one
small store hook so the phone can re-push on toggle change (parallel to
`onSkipSetChanged`), which design Decision 5 implies but does not name.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`,
`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`,
`SingleThread/SingleThreadApp.swift`, `SingleThreadWatch/SingleThreadWatchApp.swift`,
`SingleThreadTests/SkippedReminderSyncServiceTests.swift`

**Key changes**:
- `public nonisolated(unsafe) var onShowUndatedRemindersReceived: ((Bool) -> Void)?` — new receive hook on `SkippedReminderSyncService`
- `public func pushSkipIDs(_ ids: [String])` → replaced by
  `public func push(_ skipIDs: [String], showUndatedReminders: Bool)` producing one
  context `{skippedReminderIdentifiers, showUndatedReminders}`; `didReceiveApplicationContext`
  now reads both keys and fires the new hook
- `public var onShowUndatedRemindersChanged: ((Bool) -> Void)?` — new hook on
  `ReminderStore`, fired from a `didSet` on `showsUndatedReminders`
- `SingleThreadApp`: wire `store.onShowUndatedRemindersChanged` →
  `service.push(store.skippedIDs, showUndatedReminders: newValue)`; update
  `store.onSkipSetChanged` to push the combined context including
  `store.showsUndatedReminders`
- `SingleThreadWatchApp`: set `service.onShowUndatedRemindersReceived` →
  `store.showsUndatedReminders = value; await store.reload()`; update its
  `onSkipSetChanged` wiring to the combined push

**Verify**: `xcodebuild test … -only-testing:SingleThreadTests` (extended
`SkippedReminderSyncServiceTests`: combined push contains both keys; receive sets the
hook and leaves skip IDs intact; toggle `false` propagates too). Manual: toggle ON on
phone → undated reminder appears on the watch; skip a reminder on the phone → the
combined context still carries both keys (skip list is not clobbered); watch converges
after (re)connect via existing `updateApplicationContext` auto-delivery.

---

## Testing Checkpoints

- **After Phase 1**: unit suite green; phone app toggles undated reminders in/out,
  persists across relaunch; dated reminders outside the window never appear.
- **After Phase 2**: widget build/ling green; widget reflects the same toggle as the
  phone via the App Group.
- **After Phase 3**: full suite green; watch mirrors the phone toggle; skip sync and
  toggle sync share one coherent latest-wins context.
- **Final gate**: `./scripts/test.sh` (format, lint, build, Periphery, unit tests, UI
  tests + accessibility audit) — same as CI.

## Notes

- Everything slices vertically; no horizontal-only layer exists. Each later phase is
  independently testable but depends on Phase 1's two load-bearing decisions: the
  `store:`-qualified `@AppStorage` (widget) and the nil/nil fetch + window filter (all).
- Accepted risks from design (unbounded fetch when ON; high-priority undated outranking
  low-priority dated) are unchanged and need no structural work.