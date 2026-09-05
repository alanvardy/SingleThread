# Task — macOS first-class UX affordances (VAR-760)

Give the macOS build of SingleThread a native-feeling shell. Today the macOS
app is a bare `WindowGroup` whose only menu surface is card-scoped keyboard
shortcuts (`c`/`s`) and the on-card action buttons. This ticket adds: a
`CommandMenu` (and/or `.commands`) exposing the existing complete/skip
actions and appearance switching in the app menu bar; app-menu polish
(proper Quit/About entries — today only appearances are bridged in
`MacAppDelegate`); an evaluated `MenuBarExtra` live "next reminder" strip;
and a macOS-gated local-notification path for due reminders (notifications
are currently 100% `#if os(iOS)` gated), including any needed
`INFOPLIST_KEY_*` usage string.

Out of scope: WidgetKit macOS viability and macOS UI-test parity (tracked
separately if needed).