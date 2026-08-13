# Structure Outline

## Approach

Replace the `List`/`ForEach` of overdue/due-today reminders with a single
centered card showing `visibleReminders.first`, and add the app's first
EventKit write path (`save(_:commit:)`) behind a Complete button that advances
on success and holds position on failure. Two slices: display, then write-back.

---

## Phase 1: Single centered card (display-only)

Renders exactly one reminder (the earliest overdue/due-today item) in a
centered rounded-rect card instead of the list, and drops the macOS split view.
No write path yet — the card is read-only.

**Files**: `SingleThread/ContentView.swift`

**Key changes**:
- `private var currentReminder: VisibleReminder? { visibleReminders.first }` — new derived property (mirrors existing `visibleReminders` pattern).
- `ReminderCard { let visible: VisibleReminder }` — new `View` struct; `VStack(alignment: .leading)` of title + `Date.FormatStyle` due date, red when `visible.status == .overdue` (repurposes current `ReminderRow` body).
- `reminderList` `.authorized` branch: replace `List`/`ForEach` with `VStack { Spacer(); card; Spacer() }` + `.padding()`; card styling via `.regularMaterial` + `clipShape(RoundedRectangle(...))`.
- `NavigationViewWrapper<Content>` — delete, or reduce to a plain `content()` passthrough on all platforms; remove the macOS `.navigationSplitViewColumnWidth` modifier.

**Verify**: `./scripts/test.sh` green (format + lint + build + unit tests).
Manual — seed 2+ overdue/due-today reminders in the Reminders app, launch on
`iPhone 17` simulator and a macOS destination: exactly one card renders,
centered, red when overdue; empty / denied / loading states unchanged; macOS
shows the card full-window (no sidebar).

---

## Phase 2: Complete → save → advance

Adds the bottom Complete button and the store's first mutation method. Tapping
Complete sets `isCompleted`, persists via EventKit, and only on success removes
the reminder locally so the card advances instantly. On failure it shows a short
error and keeps the current card.

**Files**: `SingleThread/ReminderStore.swift`, `SingleThread/ContentView.swift`

**Key changes**:
- `ReminderStore.complete(_ reminder: EKReminder) async throws` — new. Sets `reminder.isCompleted = true`; `try eventStore.save(reminder, commit: true)`; on success `reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }`. On throw, `reminders` untouched (no removal).
- `ContentView`: `@State private var isSaving = false`, `@State private var completionError: String?` — new transient state.
- `Button("Complete")` at the bottom of the centered `VStack`; `.disabled(isSaving)`; action `do { isSaving = true; try await reminderStore.complete(current.reminder) } catch { completionError = ... }` — error surfaced as short inline `Text`/`.alert`.

**Verify**: `./scripts/test.sh` green; `make build` passes.
Manual — tap Complete: card advances to the next overdue/due-today reminder
without a fetch/flicker; completing the last shows the existing
"No overdue or due-today reminders" empty state; relaunch and the completed item
is gone from the Reminders app (persistence confirmed). Save-failure path
(e.g. Reminders sync disabled) shows the error and does **not** advance.

---

## Non-slicable notes

- `complete(_:)` is one method — the happy path (save → remove) and error path
  (throw → keep) are branches of a single `save(_:commit:)` call and cannot be
  independently-shipped slices.
- The write path is EventKit-coupled and cannot run in CI; it is verified
  manually only (per research Q6, no store/EventKit unit tests exist and none
  are planned).

## Testing Checkpoints

- **After Phase 1**: `./scripts/test.sh` green; one centered read-only card on
  iOS + macOS; all four access/empty states intact; split view gone.
- **After Phase 2**: `./scripts/test.sh` green; Complete advances on success,
  shows empty state after last, errors without advancing; persistence confirmed
  by relaunch.
