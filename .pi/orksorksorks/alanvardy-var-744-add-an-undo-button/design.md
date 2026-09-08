# Design Discussion — Undo Button (VAR-744)

## Current State

The completion flow is one-way. `ReminderStore.completeReminder(identifier:)`
(`ReminderStore.swift:163-187`) sets `isCompleted = true`, saves to EventKit,
increments `completionCounter`, sleeps 200 ms for EventKit settle, then
`reload()`s. The fetch uses `predicateForIncompleteReminders`
(`ReminderStore.swift:301`), so the completed reminder drops from
`visibleReminders` after reload. No mechanism exists to revert a completion —
the `isCompleted` flag is fire-and-forget.

The main-screen has one fixed overlay control: a gear-shaped settings button
in the **topTrailing** corner (`ContentView.swift:65-79`). The **topLeading**
corner is free. Controls are styled with `.controlPlate()` (56×56 Circle,
shadow, dark/light adaptive fill — `ControlPlateModifier.swift:12-56`) and an
SF Symbol with `.font(.title2/.title3)`.

Interface-settings toggles like `enableActionButtons`
(`InterfaceSettingsView.swift:54-63`) are `.standard`-backed `@AppStorage`
properties, not watch-synced. They flow through `SettingsBindings`
(`SettingsBindings.swift:14-77`) → sheet `.onChange` write-back
(`ContentView.swift:121-137`). New persisted keys must be added to
`UITestingSeed.persistedKeys` (`UITestingSeed.swift:56-75`).

Transient in-memory state follows the `CompletionGlow` pattern
(`CompletionGlow.swift:13-49`): `@MainActor @Observable final class`,
per-view-model instance, `trigger()` sets active + spawns a dismiss `Task`,
retrigger cancels and restarts the timer. No persistence, no App Group
involvement, no sync.

## Desired End State

- **Undo store**: An in-memory `@MainActor @Observable` class that holds the
  most recently completed `EKReminder` reference. Lives per `ReminderStore`
  instance. Cleared on new completion (single-level only).
- **Undo button**: A `.controlPlate()`-styled button in the `.topLeading`
  overlay of `ContentView`, visible only when the undo store has a retained
  reminder AND the `showUndoButton` toggle is enabled. Tapping it calls
  `ReminderStore.undoLastCompletion()`, which sets `isCompleted = false` on
  the retained `EKReminder`, saves to EventKit, clears the retained reference,
  and reloads.
- **Settings toggle**: `showUndoButton` (`@AppStorage`, `.standard`-backed,
  default `true`), rendering as a Toggle row in `InterfaceSettingsView`, wired
  through `SettingsBindings` and the sheet `.onChange` write-back. No watch
  sync.
- **UI tests**: Verify the button appears after completing a reminder and
  disappears after undo. Verify the toggle hides the button. Unit tests verify
  the undo logic (retain, revert, clear) with `InMemoryEventStore` and
  `EKReminder` fixtures.

## Patterns to Follow

- **Transient in-memory state**: `CompletionGlow` (`CompletionGlow.swift:13-49`)
  — `@MainActor @Observable final class`, stored `Task` for auto-dismiss
  (cancel-on-retrigger pattern). The undo store is simpler (no timer), but
  the class shape and injection pattern should match. ✅

- **Settings toggle plumbing**: `enableActionButtons` template —
  `@AppStorage` declaration in `ContentView.swift:172-173` (`.standard`,
  iOS-only), `SettingsBindings` bag entry (`SettingsBindings.swift:14-77`),
  `InterfaceSettingsView.swift:54-63` Toggle row, sheet `.onChange`
  write-back (`ContentView.swift:125`), `UITestingSeed.persistedKeys`
  (`UITestingSeed.swift:56-75`). ✅

- **Main-screen overlay control**: Gear button precedent
  (`ContentView.swift:65-79`) — `.overlay(alignment: .topLeading)` with
  `controlPlate()`, SF Symbol, `.accessibilityLabel`, `.accessibilityAddTraits(.isButton)`,
  padding. Same style, opposite corner. ✅

- **Unit test style**: Swift Testing (`@Test`, `#expect`), `InMemoryEventStore`
  fixtures, `@MainActor` where `EKReminder`/`ReminderStore` constructed,
  `@Suite(.serialized)` where shared defaults touched
  (`ReminderStoreTests.swift:1-6`). ✅

- **UI test style**: `--seed '<json>'` seam via `launchApp(seedJSON:)`
  (`SingleThreadUITestsFlows.swift:21-27`), `flipToggle` helper
  (`SingleThreadUITestsFlows.swift:326-339`). ✅

- **Do NOT follow**: The `SkippedReminderStore` persistence pattern
  (`ReminderSkip.swift:121-139`) — this is for persisted collections, not
  transient state. The undo store is ephemeral. ❌

- **Do NOT follow**: The `PayloadKey` + sync plumbing in
  `SkippedReminderSyncService.swift:268-282` — undo is iOS-only, no sync. ❌

## Design Decisions

1. **Retain EKReminder object, not identifier**: On completion, stash the
   `EKReminder` reference before the settle+reload drops it from the in-memory
   array. Undo sets `isCompleted = false` on the retained object, saves, and
   reloads. No re-fetch needed. The EKReminder is alive for the ~200 ms
   settle window and remains valid as long as we hold the reference. Simpler
   than identifier-based lookup, and `InMemoryEventStore` doesn't implement
   `calendarItem(withIdentifier:)`.

2. **In-memory only, no persistence**: The undo state dies when the app
   terminates — same lifetime as `CompletionGlow`. No new `UserDefaults` key,
   no `persistedKeys` entry, no App Group surface, no sync. Keeps the undo
   store simple and avoids the key-duplication convention tax.

3. **iOS-only, no watch involvement**: The undo button is main-screen iOS
   chrome. No watch undo UI is in scope. Both the toggle (`.standard`, not
   App-Group-backed) and the undo store (in-memory, per-instance) are
   phone-local by construction.

4. **Toggle in InterfaceSettingsView, `.standard`-backed**: Follows the
   `enableActionButtons` pattern exactly — it's a UI chrome preference, not a
   reminder-behavior preference. Defaults to `true` (show the button).
   `.standard` backing means no watch sync, no `PayloadKey` case, no sync
   observation diffing.

5. **Single-level undo, no stack**: Only the most-recent completion is
   undoable. A new completion overwrites the retained reference — the prior
   one is gone. This keeps the mental model simple and avoids the complexity
   of a multi-item undo history. The task does not ask for a stack.

6. **Unit tests for undo logic, UI tests for button visibility**: Unit tests
   exercise the full undo flow (retain on complete, revert on undo, clear
   after undo, overwrite on second complete) in `ReminderStoreTests` with
   `InMemoryEventStore`. UI tests verify the button appears/disappears via the
   seed seam and the toggle works via `flipToggle`. No extension to
   `InMemoryEventStore` needed since we retain the EKReminder object, not the
   identifier.

## What We're NOT Doing

- **No persistence** of undo state across app termination
- **No watch undo button** or watch-side undo logic
- **No watch sync** for the `showUndoButton` toggle
- **No multi-level undo stack** — single-level only
- **No undo for delete or skip** — completion only
- **No identifier-based re-fetch** from EventKit for undo
- **No `PayloadKey` entry** in `SkippedReminderSyncService`
- **No new `persistedKeys` entry** in `UITestingSeed`

## Open Risks

- **EKReminder mutability across reload**: The retained `EKReminder` reference
  persists across the settle+reload. `reload()` calls `fetchReminders` which
  replaces the in-memory `reminders` array and filters for incomplete. The
  retained EKReminder is a separate reference — not pulled from the new array
  — so it should remain untouched. Verify this holds in testing; if EventKit
  mutates the underlying object on save, we'd need to copy key fields before
  reload.

- **Undo during freemium gate**: If the user completes their 100th free
  reminder (gate flips off), can they undo it? The undo flow would bypass
  `completeReminder`'s gate check since it's a separate method. Decide
  whether undo should decrement `completionCounter` — if it doesn't, the gate
  stays closed and the user can't re-complete. If it does, the counter is no
  longer strictly monotonic (the `CompletionCounterStore` has no `decrement()`
  method today). Worth flagging as a follow-up decision during implementation.

- **Undo button and `canMutate`**: If the user has no mutations remaining
  (gate closed) but has an undoable completion, should the undo button still
  appear? Undo is technically a mutation. We should gate it the same way —
  `canMutate == false` hides the button regardless of undo state.