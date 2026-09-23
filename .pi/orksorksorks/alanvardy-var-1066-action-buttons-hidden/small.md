# Task

Fix a bug where the iOS main screen hides the action buttons (Complete · mic · Skip cluster) on app open, even though "action buttons" is enabled in settings and there is an active reminder to process. The user only sees the buttons after a partial left/right swipe (a re-render pass) forces them to appear.

**Root cause (from recon):** the visibility gate
`ContentViewModel.showsActionButtons` (`SingleThread/ContentViewModel.swift:83-85`)
is a plain computed `Bool` over two non-observable inputs — a plain
`var enableActionButtons` (`:74-77`, set once at startup via
`ContentView.swift:283-285` `.task`) and `store.visibleReminders` (derived in
`SingleThreadCore/.../ReminderStore.swift:173`). Nothing observable back-ends
the `.if showsActionButtons` branch (`ContentView.swift:749-750`), so on the
initial open path — where the flag is injected before reminders finish loading,
at which point `visibleReminders.first == nil` — SwiftUI has no dependency to
re-evaluate the branch when reminders later land. Toggling the setting off/on
doesn't recompute either, matching the reported symptom.

**What to build:** make the action-buttons visibility decision recompute when
the reminder set settles, so the cluster appears as soon as conditions are met
without requiring a swipe. The change is localized to the SingleThread view
layer: make the gate/its inputs reactive (or otherwise ensure a refresh fires
when reminders land) in `ContentViewModel.swift` and the injection/refresh
handling in `ContentView.swift`. Do not change behavior beyond this — buttons
must still be hidden when disabled or when `visibleReminders.first == nil`
genuinely, and visible when enabled and a reminder is present.

**Acceptance:** with action buttons enabled and a visible reminder, the cluster
renders without any user interaction (no swipe) after returning to the main
screen; with the flag off or no visible reminder, they stay hidden. A unit
test reproduces the failure (simulate the flag being injected before reminders
load, then assert the gate comes alive) and the fix makes it pass.

## Why SMALL
Single-module fix (SingleThread view layer) of ~2 source + 1–2 test files
following an existing reactive/`onChange` pattern; the existing
`ActionButtonTests` seam already asserts `showsActionButtons` directly. Root
cause known, no schema/migration, no new subsystem/integration, no shared/
convention-code or backward-compat risk, no human design sign-off, and tests
are few/local to the change.

## Key files
- `SingleThread/ContentViewModel.swift:74-85` — `enableActionButtons` plain var, `showsActionButtons` computed gate.
- `SingleThread/ContentView.swift:283-285` (`.task` flag injection), `:292-294` (`.onChange`), `:749-750` (render branch), `:100-101` (`@AppStorage("enableActionButtons")`).
- `SingleThreadCore/Sources/SingleThreadCore/ActionMenuGate.swift:10-12` + `ReminderStore.swift:173` (`visibleReminders`) — only if the chosen fix pulls store-change notification; the root lives in the view layer, so prefer not to expand scope here.
- Tests: `SingleThreadTests/ActionButtonTests.swift` (add a startup-path regression), optionally `SingleThreadUITests/SingleThreadUITests.swift:26` `testLaunchAndRenderSmoke` (renders the cluster on open).