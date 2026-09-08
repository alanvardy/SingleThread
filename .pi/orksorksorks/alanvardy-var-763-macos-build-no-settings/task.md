# Task — VAR-763: macOS build shows no settings

On the macOS build of the SingleThread app, opening the settings screen shows
only the "Done" toolbar button — none of the settings rows/content render, while
on iOS the same screen shows all rows correctly. The goal is to find why the
settings content fails to render on macOS and make it appear, without changing
behavior on iOS.

The settings screen is a modal SwiftUI sheet (`SettingsView`) presented from
`ContentView` via a gear button (`settingsButton`), shared by the iOS and macOS
targets of a single application target.