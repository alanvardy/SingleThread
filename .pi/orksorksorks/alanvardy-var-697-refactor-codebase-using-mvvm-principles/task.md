# Task: Refactor codebase using MVVM principles (VAR-697)

SingleThread is an iOS + watchOS + macOS Reminders client. The goal is to
restructure the app so view logic and app-coordination move out of the SwiftUI
view structs into explicit ViewModels (and leaner wiring at the app entry
point), following Model-View-ViewModel conventions. Today much of the
presentation state and side-effect orchestration (dictation, settings
bindings, WatchConnectivity + widget wiring, computed presentation state)
lives inline in `ContentView`, `SettingsView`, and the `SingleThreadApp`
`init`. The refactor should introduce clearly separated ViewModel layers
across the iOS, watchOS, and macOS surfaces while preserving behavior and
the existing test seams.
