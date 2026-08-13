# Structure Outline

## Approach

Replace the SwiftData/`Item` list with a live EventKit fetch: a
`@MainActor @Observable` `ReminderStore` requests full Reminders access and
fetches incomplete reminders, a pure classifier narrows them to overdue-or-today,
and `ContentView` renders the sorted list. iOS + macOS; visionOS renders a
"not supported" state.

## Phase 1: Due-status classifier (pure, unit-tested)

Extract the overdue/today filtering rule into a standalone pure function with no
EventKit dependency, and replace the empty test scaffold with real boundary
tests. This establishes the rule every later phase consumes.

**Files**: `SingleThread/ReminderFilter.swift` (new),
`SingleThreadTests/SingleThreadTests.swift` (rewrite)

**Key changes**:
- `enum DueStatus { case overdue, dueToday }` — new type.
- `func dueStatus(dueDateComponents: DateComponents?, isCompleted: Bool, now: Date, calendar: Calendar) -> DueStatus?` — returns `nil` to exclude (completed, or no due date); `.overdue` when `calendar.date(from: components) < calendar.startOfDay(for: now)`; `.dueToday` when it falls on `startOfDay(for: now)`.

Boundary tests to pin: completed → `nil`; `nil` due date → `nil`;
yesterday 23:59 → `.overdue`; today 00:00 → `.dueToday`; today 23:59 →
`.dueToday`; tomorrow 00:00 → `nil`; injected calendar/timezone for the
00:30-local edge case.

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes; `./scripts/test.sh` green.

---

## Phase 2: Reminder access — permissions, entitlements, `ReminderStore`

Add the EventKit access layer: usage-description key, macOS entitlement, and a
`ReminderStore` that owns the `EKEventStore`, requests access, and fetches. The
app can now request and read reminders (not yet displayed).

**Files**: `SingleThread/ReminderStore.swift` (new),
`SingleThread/SingleThread.entitlements` (new),
`SingleThread.xcodeproj/project.pbxproj` (edit),
`SingleThread/SingleThreadApp.swift` (edit)

**Key changes**:
- `enum ReminderAccessStatus { case notDetermined, denied, authorized }` — new type.
- `@MainActor @Observable final class ReminderStore { let eventStore: EKEventStore; private(set) var accessStatus: ReminderAccessStatus = .notDetermined; private(set) var reminders: [EKReminder] = []; func load() async }` — `load()` calls `requestFullAccessToReminders()`, then `fetchReminders(matching:)` with an incomplete-reminders predicate, storing raw results (filtering is the view's job via Phase 1).
- pbxproj: `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` in both Debug and Release configs; `CODE_SIGN_ENTITLEMENTS = SingleThread/SingleThread.entitlements`. Note: `.entitlements` is **not** auto-discovered like `.swift` files — it needs a pbxproj file reference plus the build setting.
- Entitlements: `com.apple.security.personal-information.calendars = true` (macOS-only; iOS ignores it harmlessly).
- `SingleThreadApp`: `@State private var reminderStore = ReminderStore()` and `.environment(reminderStore)` on the `WindowGroup` (SwiftData still present this phase).

**Verify**: `xcodebuild build` on iOS (`iPhone 17`) and macOS (`platform=macOS`) destinations succeed; manual: launch → TCC prompt appears, grant → `reminders.count` populates (temporary debug print). The macOS entitlement path is **manual-only — not covered by CI**, so verify it by hand here.

---

## Phase 3: Reminders list UI + remove SwiftData

Swap `ContentView` from the `@Query` list to a `ReminderStore`-driven list and
delete all `Item`/SwiftData wiring. Deliverable: sorted qualifying reminders with
overdue styling.

**Files**: `SingleThread/ContentView.swift` (rewrite),
`SingleThread/SingleThreadApp.swift` (edit), `SingleThread/Item.swift` (delete)

**Key changes**:
- `ContentView`: `@Environment(ReminderStore.self) private var reminderStore`; `private var visibleReminders: [(reminder: EKReminder, status: DueStatus)]` — filter via `dueStatus`, sort ascending by `calendar.date(from: dueDateComponents)`; `.task { await reminderStore.load() }`.
- Row: title + due-date text in **one shared row view**; overdue rows `.foregroundStyle(.red)`.
- Delete `@Query private var items`, `@Environment(\.modelContext)`, `addItem`/`deleteItems`, and the toolbar; update `NavigationViewWrapper`'s `Text("Select an item")` detail to a neutral string.
- `SingleThreadApp`: plain `WindowGroup { ContentView() }` — remove `sharedModelContainer`, `Schema`, `ModelConfiguration`, `.modelContainer`.
- `#Preview`: drop `.modelContainer(for: Item.self, inMemory: true)`; use `.environment(ReminderStore())`.

**Verify**: `./scripts/test.sh` green; `grep -rE 'Item|@Query|modelContext' SingleThread/` returns nothing (no dangling SwiftData); manual: iOS launch → grant → list shows exactly the incomplete overdue-or-today reminders, ascending, overdue in red.

---

## Phase 4: Access states, refresh, platform guards

Render the store's non-authorized/empty states, re-load on foreground, and gate
reminder code so visionOS compiles to a "not supported" state.

**Files**: `SingleThread/ContentView.swift` (edit)

**Key changes**:
- State rendering on `accessStatus`: `.denied` → "Reminders access denied" message; `.notDetermined` → awaiting state; `.authorized` with no `visibleReminders` → "No overdue or due-today reminders"; otherwise the list.
- Foreground refresh: `@Environment(\.scenePhase) private var scenePhase`; `.onChange(of: scenePhase) { if newPhase == .active { Task { await reminderStore.load() } } }`.
- `#if os(iOS) || os(macOS)` around reminder code; `#else` (visionOS) → "Not supported on this device".
- `#Preview`: `.environment(ReminderStore())` — EventKit isn't stub-able in previews, so the preview shows the `notDetermined`/empty state, which is acceptable.

**Verify**: `xcodebuild build` succeeds for iOS, macOS, and a visionOS simulator destination; manual: deny access → denied message; grant with no qualifying reminders → empty message; background then foreground → list refreshes.

## Testing Checkpoints

- **After P1**: classifier tests green under `./scripts/test.sh`; rule pinned at day boundaries.
- **After P2**: iOS + macOS builds; TCC prompt and fetch verified manually; entitlement wired (manual, not in CI).
- **After P3**: `./scripts/test.sh` green with zero SwiftData/`Item` references; list renders real reminders.
- **After P4**: all three platforms build; denied/empty/refresh states render correctly.
