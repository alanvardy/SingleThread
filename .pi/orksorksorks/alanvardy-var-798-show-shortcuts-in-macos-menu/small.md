# Task

Show the complete and skip keyboard shortcuts (`c` and `s`) in the app's macOS menu bar extra — the `MenuBarExtra` (`.menuBarExtraStyle(.menu)`) wired in `SingleThreadApp.swift:33-44`, whose content is `MenuBarExtraOptions` (`SingleThread/MenuBarExtraOptions.swift`, `#if os(macOS)`).

Today the menu's Complete and Skip buttons (`MenuBarExtraOptions.swift:25-30`) show no shortcut hint, even though the same actions already carry `.keyboardShortcut("c", modifiers: [])` / `.keyboardShortcut("s", modifiers: [])` on the macOS bottom-bar buttons in `SingleThread/ContentView+ActionMenu.swift` (lines 106 / 131 / 147). The goal: the menu surfaces the `c`/`s` keys to the user — e.g. by attaching the matching `.keyboardShortcut(...)` to the menu's Complete/Skip buttons (macOS renders the key-equivalent hint on menu items) and/or by appending a literal `c` / `s` hint to the button labels, reusing the existing `SharedStrings.completeReminder` / `SharedStrings.skipReminder` labels.

Coverage: extend `SingleThreadTests/MenuBarExtraOptionsTests.swift` — `rendersNextReminderActions` (lines 16-24) asserts on `String(describing:)`, so a text hint is directly assertable; verify red-first that any chosen rendering is reflected by the describing output (or by the modifier chain), and that at least one case actually runs. Prefer not introducing new localized strings (avoid touching Shared Core's `LocalizedString+Shared.swift` / `Localizable.xcstrings`) — reuse existing labels.

Also: the branch's `DELETEME` marker is still untracked-deleted (`git status`); run `git rm DELETEME` before merging. And follow `~/.pi/agent/AGENTS.md` + repo `AGENTS.md` before-committing gates (`make format`/`make lint` in-line, `./scripts/test.sh` gate via run-gate, unit-test names must not start with `test`/`testing`).

## Why SMALL
All of A–F hold: one app-local macOS-only View + its existing unit-test suite (2 files, no new build/CI/pbxproj/test-infra change); approach known from the existing `keyboardShortcut` declarations in `ContentView+ActionMenu.swift`; no schema, no new subsystem/integration, no shared/convention-owned code required; 0-2 resolvable unknowns; tests few and local.

## Key files
- `SingleThread/MenuBarExtraOptions.swift` — Complete/Skip buttons at lines 25-30; add the `c`/`s` hint here.
- `SingleThreadTests/MenuBarExtraOptionsTests.swift` — extend `rendersNextReminderActions` (lines 16-24); `rendersNothingWhenNoReminderDue` unchanged.
- Precedent: `SingleThread/ContentView+ActionMenu.swift` lines 106/131/147 (existing `.keyboardShortcut("c"/"s", modifiers: [])` on the macOS bottom-bar controls).
- Reuse `SharedStrings.completeReminder` / `skipReminder` (`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:21-22, 36-37`) — do not add new catalog entries.
- Do NOT touch: `SingleThreadApp.swift` wiring, `MenuBarExtraPreference`, watch/widget, `SingleThreadUITests` (no macOS menu UI test exists and none is required here).