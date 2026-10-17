# Task

In the app's Settings screen, the "Reminders" row and the "Notifications" row
use the same SF Symbol (`bell.badge`), so they look identical. Give the
Reminders entry its own distinct, semantically appropriate SF Symbol
(e.g. a checklist/reminder-style symbol such as `checklist` or
`list.bullet.clipboard`), leaving the Notifications row on `bell.badge`.

Scope:
- `SingleThread/SettingsView.swift` — the `SettingsLinkLabel` for the
  Reminders section (line ~96) currently uses `systemImage: "bell.badge"`;
  change only that one. The Notifications label (line ~104) and the
  `NotificationsSettingsView.swift` bell icon stay as they are.
- Update the fixture/expectation in `SingleThreadTests/SettingsCaptionTests.swift`
  (line ~42) if it pins the Reminders row's icon.
- Keep the accessibility label unchanged; only the icon changes.

Verify the chosen symbol exists in the deployment target's SF Symbols set
(compile/build is the check), run `make format`/`make lint`, and build.

# Why SMALL

A. Single module, one source file (plus possibly one test fixture), follows
   the existing `SettingsLinkLabel(systemImage:)` pattern.
B. No unknowns beyond choosing a valid SF Symbol.
C. No schema/migration.
D. No new subsystem, shared code, or convention change.
E. No product/design trade-off needing sign-off — just a different icon.
F. Test surface is local (at most one existing fixture assertion).

# Key files

- `SingleThread/SettingsView.swift` — lines ~94–105, the two `bell.badge` rows.
- `SingleThread/SettingsCaption.swift` — `SettingsCaption`/`SettingsLinkLabel`
  (`systemImage` property).
- `SingleThreadTests/SettingsCaptionTests.swift` — line ~42 fixture.
- `SingleThread/NotificationsSettingsView.swift` — has its own `bell.badge`;
  do not change (only referenced so it is not confused with the Reminders row).
