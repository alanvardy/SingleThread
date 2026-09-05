# Task — Add refresh button for macOS

VAR-788: The macOS build of SingleThread has no way to manually refresh the reminder list (it lacks the pull-to-refresh gesture available on iOS). Add a refresh button positioned in the top left-hand corner of the macOS UI that reloads the reminders.

The feature must ship with unit and UI test coverage and pass the full CI gate (`./scripts/test.sh`) per project conventions.