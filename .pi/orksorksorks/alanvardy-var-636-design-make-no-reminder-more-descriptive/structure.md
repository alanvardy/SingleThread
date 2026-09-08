# Structure Outline

## Approach

Add a `hasHiddenReminders` signal to `ReminderStore` (the single source of truth for iOS, watch, and widget), computed during `reload()` by comparing the broad incomplete-reminder set against the windowed `shown` set. The iOS "No Reminders" empty branch then splits into two contextual variants (truly-empty vs. "nothing due today") that stay copy/icon-driven over the existing `ContentUnavailableView`; the same signal rolls to the watch and widget empty states.

> **Go-back note (constraint from codebase):** the design computes `hasHidden` only in `reload()`, but previews/unit tests seed the store via the `ReminderStore(loadsReminders:, reminders:, …)` init, which never runs `reload()` nor touches EventKit. The seeded init **must** gain an optional `hasHidden:` param (and a pure derivation helper) or the hidden sub-state cannot be previewed or unit-tested. This is a design-compatible addition, not a redesign; captured in Phase 1.

---

## Phase 1: Store signals + seedable detection

Establishes the `hasHidden` fact in Core so every upper surface can branch on it, and makes detection testable without EventKit.

**Files**: `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`

**Key changes**:
- `public private(set) var hasHidden: Bool = false` — new derived property (design: `hasHiddenReminders`).
- `public func reload(clearSkipped: Bool = false) async` — modified: when `showsUndatedReminders` is false, run one extra broad fetch (nil/nil predicate) and set `hasHidden = <derived>`; when true, the in-hand fetch is already broad, so derive from `fetched` vs `shown`.
- New `public init(loadsReminders:, reminders:, skippedIDs:, authorizationStatus:, excludedProjectTitles: [String] = [], hasHidden: Bool = false)` — extended preview/test init accepting the pre-seeded signal.
- Pure helper for the derivation, e.g. `ReminderStore.hasHiddenFor(shown: [EKReminder], allIncomplete: [EKReminder]) -> Bool` — new, unit-testable without EventKit (true when `allIncomplete.count > shown.count` / any id not in `shown`).

**Verify**: `xcodebuild … -only-testing:SingleThreadCore` passes with new derivation tests; full build compiles. Manual: none yet (no user-visible change).

---

## Phase 2: iOS contextual empty state

Splits the iOS empty branch into two copy/icon variants driven by `store.hasHidden`, keeping the existing affordances (pull-to-refresh + mic `bottomBar`).

**Files**: `SingleThread/ContentView.swift`, `SingleThreadTests/SingleThreadTests.swift`

**Changes**:
- Empty branch (`store.reminders.isEmpty`, `ContentView.swift:251-265`) — modified: if `store.hasHidden`, render `ContentUnavailableView("Nothing due", systemImage: "calendar", description: Text("Only today's and overdue reminders show here — pull to refresh."))`; else keep `"No Reminders"` / `"checklist"` with the descriptive body. `bottomBar` + `.refreshable { await store.reload() }` stay.
- `#Preview("Empty")` — extended/added so `ContentView(loadsReminders: false)` seeds `hasHidden: false` **and** `hasHidden: true` (two previews).

**Verify**: `xcodebuild … -only-testing:SingleThreadTests` passes — new `String(describing: view.body)` assertions on both body strings. Manual: run `#Preview("Empty")` over Quartz simulator, confirm both variants + icons render and mic/pull-to-refresh still work.

---

## Phase 3: Roll out to watch + widget

Applies the developer's signal to the companion surfaces for a consistent "nothing due, here's why" presentment.

**Files**: `SingleThreadWatch/WatchReminderView.swift`, `SingleThreadWidget/NextThingWidget.swift`

**Changes**:
- `noRemindersState` (watch `WatchReminderView.swift:110`) — add `Text(description)` child under the `"No Reminders"` headline (hidden → "Nothing due right now", else "No reminders yet"), keeping the existing `refreshButton`.
- Widget `makeEntry()`/`.empty` (`NextThingWidget.swift:62-66,95-96`) — pass a real `message:` into the existing `messageView` (e.g. `hasHidden ? "Nothing due right now" : "No reminders yet"`) instead of `nil`.

**Verify**: build watch + widget targets pass; previews (`#Preview("No Reminders")`) show the description; accessible description remains a `Text`.

---

## Phase 4: Test hardening, UI comment fix, full CI

Correct the stale UI-test assumption, lock the copy, and run the full gate.

**Files**: `SingleThreadUITests/SingleThreadUITests.swift`, `SingleThreadTests/SingleThreadTests.swift`

**Changes**:
- Fix stale comment (`:22-23`): `--ui-testing` + `loadsReminders: false` renders the empty `reminderList` branch, not "Requesting access…".
- Add missing placeholder-string assertions for All Done / truly-empty / hidden variants if Phase 2 coverage is thin.
- No production-signature changes.

**Verify**: `./scripts/test.sh` passes end-to-end (format, lint, build, Periphery, unit, UI/accessibility, SwiftFormat/SwiftLint strict).

---

## Testing Checkpoints

- **After Phase 1**: `ReminderStore.hasHidden` exists and is seeded via init; derivation unit test green; build compiles. (No visible change yet.)
- **After Phase 2**: iOS empty branch shows two distinct bodies/icons; copy unit tests green; previews both sub-states; mic + pull-to-refresh unaffected.
- **After Phase 3**: watch and widget show a matching description; iOS/watch/widget all agree on the same hidden signal.
- **After Phase 4**: full `./scripts/test.sh` gate is green; stale `--ui-testing` comment corrected.

## Explicitly non-sliceable

- **The broad `reload()` EventKit fetch** can't be unit-tested (integration-only; needs a live store). Guarded by the Phase 1 pure helper + Phase 2 seeded tests for derivation; real fetch covered by manual/integration only. Watch must confirm a cheap broad fetch is available read-only (Open Risk).
- **The two iOS variants** share the branch's `bottomBar`/`.refreshable` — they must be changed together, else copy and affordances diverge mid-phase.