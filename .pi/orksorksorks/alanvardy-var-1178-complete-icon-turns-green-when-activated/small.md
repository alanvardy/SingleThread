# Task

Linear VAR-1178 — "Complete icon turns green when activated." Temporarily turn
the complete icon green when completing a task, lasting **just as long as the
green screen flash**.

## Current state on this branch

An earlier commit (`62616b49 feat(complete): tint the complete toolbar item
green on success`) already made the iOS complete toolbar icon turn green:
`SingleThread/ContentView+Toolbar.swift` `completeToolbarLabel` renders
`Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")`
with `.foregroundStyle(.green)` when `viewModel.completionFlash.isActive`.

The remaining gap is **duration**. The icon's green is driven by
`CompletionFlash.duration` (`SingleThread/CompletionFlash.swift`), which
defaults to `CreationFeedback.displayDuration` = **1.0 s**
(`SingleThread/CreationFeedback.swift`). The green screen flash is driven by
`CompletionGlow.duration` = **0.50 s**
(`SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift`). So today
the icon stays green roughly twice as long as the flash.

## What to build

Make the complete icon's green last the same time as the green screen flash —
i.e. tie `CompletionFlash.duration` (or the value used for the completion-icon
green) to the glow duration (0.50 s), following the same
`trigger → Task.sleep(duration) → isActive = false` pattern the two classes
already share. Keep the change localized to the completion icon's green
duration; do not regress the dictation checkmark's own `CreationFeedback`
timing.

Note: `completionFlash.trigger()` in `SingleThread/ContentViewModel.swift` runs
unconditionally on success, while the glow is gated by
`showCompletionGlow.isEnabled`; only the duration needs to change here.

## Why SMALL

Single app-target UI/timing change (≤~5 files, no `SingleThreadCore` change
required), follows the existing transient-state pattern (A), no unknowns or new
API (B), no schema (C), no new subsystem/shared code (D), no human design
decision (E), and only local test updates (F).

## Key files

- `SingleThread/CompletionFlash.swift` — icon green state + `duration` (the
  thing to change).
- `SingleThread/CreationFeedback.swift` — `displayDuration = 1.0` currently
  used as the flash default.
- `SingleThreadCore/Sources/SingleThreadCore/CompletionGlow.swift` — glow
  `duration = 0.50` (source of truth for the flash length).
- `SingleThread/ContentView+Toolbar.swift` (`completeToolbarLabel`, L144–153)
  — where the icon is tinted green.
- `SingleThread/ContentViewModel.swift` L191 — `completionFlash.trigger()`.
- `SingleThreadTests/CompletionFlashTests.swift` — update
  `defaultDurationMatchesDictationCheckmark` (L43–45) and add an assertion
  tying the completion-icon duration to `CompletionGlow.duration`.
- Optional: `SingleThread/ContentView+ActionMenu.swift` `macCompleteButton`
  (L117–131) if the macOS icon should tint too — confirm scope; no UI test
  currently covers the glow or green tint.
