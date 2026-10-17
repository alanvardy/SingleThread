# Task

Improve the watchOS "No Reminders" empty state (VAR-1133). Today the watch empty
state renders three things stacked vertically:

- the title "No Reminders"
- a caption line that reads either "No reminders yet" (default) or
  "Nothing due right now" (when reminders are hidden/skipped)
- a "Refresh" button

Remove the "No reminders yet" caption text from the watch screen. Keep the title
and the Refresh button. Preserve the hidden-reminders variant ("Nothing due
right now") unless removing the whole caption line is the cleaner, obviously
intended reading — the ticket only names "No reminders yet", so the safest
minimal change is to drop the default caption while keeping the "nothing due"
message when reminders are hidden. Note that `SharedStrings.noRemindersYet` is
also used by `SingleThreadWidget/NextThingWidget.swift`, so do not delete or
change the shared string itself; only the watch view's usage of it.

Verify the resulting watch empty-state layout still looks correct (spacing in
the `VStack`), adjust spacing only if the removal leaves an obvious gap, and run
the project gate (format, lint, relevant watch build/tests). Since this is a
pure view-copy change, a new unit test is not required unless existing copy
tests assert on the removed string.

## Why SMALL

A. Single view file (`SingleThreadWatch/WatchReminderView.swift`, one `VStack`
in `noRemindersState`), no new pattern.
B. No unknowns; the exact line and shared string usage are already located.
C. No schema/migration.
D. No new subsystem/shared-convention change; the shared localization resource
is intentionally left untouched because the widget still uses it.
E. No design decision or human sign-off.
F. No new test surface — existing empty-state tests do not reference this string.

## Key files

- `SingleThreadWatch/WatchReminderView.swift` — `noRemindersState(hasHidden:)`
  (~line 228) renders the title, the caption, and `refreshButton`.
- `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift` —
  `SharedStrings.noRemindersYet` (~line 101) is shared with the widget; leave it.
- `SingleThreadWidget/NextThingWidget.swift:~126` — other consumer of
  `noRemindersYet`; must keep working.
- `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` —
  "No reminders yet" entry stays because the widget still uses it.
- `SingleThreadWatch/WatchReminderView.swift:436` — `#Preview("No Reminders")`
  for manual visual check.
