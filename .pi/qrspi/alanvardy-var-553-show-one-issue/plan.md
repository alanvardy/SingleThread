# Implementation Plan

## Overview

Replace the `List`/`ForEach` of overdue/due-today reminders with a single centered
card showing `visibleReminders.first`, and add the app's first EventKit write path
(`save(_:commit:)`) behind a Complete button that advances on success and holds
position on failure.

---

## Phase 1: Single centered card (display-only)

Renders exactly one reminder (the earliest overdue/due-today item) in a centered
rounded-rect card instead of the list, and drops the macOS split view. No write
path yet — the card is read-only.

### Changes

#### 1. Add `currentReminder` derived property
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add below the existing `visibleReminders` computed property (in the `// MARK: Private` section, near line 35-51):

```swift
private var currentReminder: VisibleReminder? {
    visibleReminders.first
}
```

#### 2. Replace `ReminderRow` with a card-styled `ReminderCard`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete `ReminderRow` (currently ~lines 86-97) and add `ReminderCard` in its place.
It reuses the `ReminderRow` body and adds a material fill + rounded clip:

```swift
private struct ReminderCard: View {
    let visible: VisibleReminder

    var body: some View {
        VStack(alignment: .leading) {
            Text(visible.reminder.title ?? "Untitled")
            Text(visible.dueDate, format: Date.FormatStyle(date: .numeric, time: .standard))
                .font(.caption)
        }
        .foregroundStyle(visible.status == .overdue ? Color.red : Color.primary)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

#### 3. Replace the `.authorized` list branch with a centered card
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In `reminderList` (the `@ViewBuilder` computed property), replace the
`else { List { ForEach … } … }` block with a centered `VStack`:

```swift
case .authorized:
    if let current = currentReminder {
        VStack {
            Spacer()
            ReminderCard(visible: current)
            Spacer()
        }
        .padding()
    } else {
        ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")
    }
```

The empty state (`visibleReminders.isEmpty` → `ContentUnavailableView`) is
preserved unchanged; only the non-empty branch changes. The macOS-only
`.navigationSplitViewColumnWidth` modifier dies with the `List` — remove it.

#### 4. Delete `NavigationViewWrapper` and unwrap `body`
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Delete the entire `NavigationViewWrapper` struct (~lines 99-113) and change
`body` to render `reminderList` directly (`.task` / `.onChange` move onto it):

```swift
var body: some View {
    reminderList
        .task {
            await reminderStore.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await reminderStore.load()
                }
            }
        }
}
```

### Verification

#### Automated
- [x] `./scripts/test.sh` passes (SwiftFormat + SwiftFormat lint + SwiftLint `--strict` + `xcodebuild` Debug build on `iPhone 17` + unit tests)
- [x] `make build` passes

#### Manual
- [ ] Seed 2+ reminders in the Reminders app with due dates: at least one overdue (yesterday) and one due today. On the simulator, open the Reminders app and add them to a local ("On My iPhone") list.
- [ ] Launch on `iPhone 17` simulator (⌘R in Xcode, or `xcodebuild -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' build` then `xcrun simctl install booted <DerivedData path to SingleThread.app>` + `xcrun simctl launch booted app.alanvardy.SingleThread`): exactly one card renders (the earliest due), centered; overdue card text is red.
- [ ] Build & run the macOS destination (`xcodebuild -scheme SingleThread -destination 'platform=macOS' build`, then open the built app): card renders centered in the full window with **no** sidebar and no "Select a reminder" detail pane.
- [ ] Empty (no qualifying reminders), denied (revoke Reminders access in System Settings), and loading (`ProgressView`) states still render as before.

---

## Phase 2: Complete → save → advance

Adds the bottom Complete button and the store's first mutation method. Tapping
Complete sets `isCompleted`, persists via EventKit, and only on success removes
the reminder locally so the card advances instantly. On failure it shows a short
error and keeps the current card.

### Changes

#### 1. Add `complete(_:)` to `ReminderStore`
**File**: `SingleThread/ReminderStore.swift`
**Action**: modify

Add below `load()` (in the `// MARK: Internal` section):

```swift
func complete(_ reminder: EKReminder) async throws {
    reminder.isCompleted = true
    try eventStore.save(reminder, commit: true)
    reminders.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
}
```

Notes for the implementer:
- `eventStore.save(_:commit:)` is synchronous; `async` is retained per the design
  so the method signature leaves room for a non-blocking write later. The call
  runs on the main actor (the class is `@MainActor`), which is acceptable for
  this first write path.
- `reminders` is `private(set)`, but `complete(_:)` is a member so it may mutate
  it directly.
- On throw (before the `removeAll` line), `reminders` is untouched, so the
  current card holds position. On success, removal mutates the observable
  `reminders`, which re-renders the view and makes `currentReminder` the next
  sorted item instantly (no refetch/flicker).

#### 2. Add saving/error state and the Complete button
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Add two `@State` properties next to the existing `@Environment` properties
(Private section, ~line 32):

```swift
@State private var isSaving = false
@State private var completionError: String?
```

Extend the centered `VStack` from Phase 1 with the button and an inline error
line:

```swift
case .authorized:
    if let current = currentReminder {
        VStack {
            Spacer()
            ReminderCard(visible: current)
            Spacer()
            Button("Complete") {
                complete(current)
            }
            .disabled(isSaving)
            if let completionError {
                Text(completionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    } else {
        ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")
    }
```

Add the `complete(_:)` helper in the `// MARK: Private` section:

```swift
private func complete(_ visible: VisibleReminder) {
    isSaving = true
    Task {
        defer { isSaving = false }
        do {
            try await reminderStore.complete(visible.reminder)
            completionError = nil
        } catch {
            completionError = "Couldn't complete the reminder. Please try again."
        }
    }
}
```

Notes for the implementer:
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set project-wide, so do **not**
  wrap the task in `Task { @MainActor in }` — plain `Task {}` already inherits
  `MainActor`. `isSaving`/`completionError` are mutated safely on the main actor.
- The button is `.disabled(isSaving)` to prevent double-taps while a save is in
  flight.

### Verification

#### Automated
- [ ] `./scripts/test.sh` passes (formats the code first, then format-lint, SwiftLint `--strict`, Debug build on `iPhone 17`, unit tests)
- [ ] `make build` passes
- [ ] `make test` passes (all 7 existing `dueStatus` unit tests remain green — no test changes required)

#### Manual
- [ ] Launch on `iPhone 17` simulator with 2+ overdue/due-today reminders seeded: tapping **Complete** on the first card immediately advances to the next reminder with no visible fetch/flicker.
- [ ] Complete the last qualifying reminder: the existing "No overdue or due-today reminders" empty state appears.
- [ ] Relaunch the app (and/or open the Reminders app): the completed item is gone — persistence to the system Reminders store confirmed.
- [ ] Save-failure path: with Reminders sync/access broken (e.g. revoke write access or disable Reminders syncing), tapping Complete shows the short red error message and the card does **not** advance; the reminder stays current for a retry.

---

## Non-slicable notes

- `complete(_:)` is one method — the happy path (save → remove) and error path
  (throw → keep) are branches of a single `save(_:commit:)` call and cannot be
  independently shipped slices.
- The write path is EventKit-coupled and cannot run in CI; it is verified
  manually only (no store/EventKit unit tests exist and none are planned).

## Deviations from the structure outline

1. `NavigationViewWrapper` is **deleted outright** rather than reduced to a
   passthrough — a passthrough on all platforms has no purpose once the split
   view is gone; `body` renders `reminderList` directly (structure allowed either).
2. `ReminderRow` is **renamed to `ReminderCard`** (structure said "repurposes
   current ReminderRow body"); it's the same body plus the material/clip styling.
3. Save-failure is surfaced as an **inline caption `Text`** (red) rather than an
   `.alert` — simpler (no presentation binding) and matches the "short inline
   Text" option the structure named.
