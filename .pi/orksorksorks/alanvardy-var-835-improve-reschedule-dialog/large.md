# Task

Polish the clunky reschedule dialog: place the "Reschedule to" label and the date
picker next to each other and centered, and restyle the "Reschedule" confirm
button underneath to match the app's other buttons and center it. The reschedule
dialog exists as parallel implementations on **both** iOS (`SingleThread/RescheduleSheet.swift`,
used by the skip-nudge sheet and the action menu) and watchOS
(`SingleThreadWatch/WatchReminderView.swift` `actionMenuRescheduleSheet`), and
the ticket does not say which — or whether both — is in scope.

## Why LARGE
- **MULTI_MODULE** — the dialog is implemented twice, in the iOS app module and
  the watchOS app module; fixing both touches two subsystems and ~4-7 files
  (both sheets + iOS callers `ContentView+ActionMenu.swift` / `ContentView+iOS.swift` + tests).
- **CROSS_CUTTING** — UI surfaces on two platform targets (iOS + watchOS), not a
  single localized view.
- **UNKNOWNS** — which dialog(s) the ticket targets is unstated (both match the
  description verbatim), and "similar styling to the rest of the app" needs a
  per-platform design read (the iOS sheet's `Label("Reschedule", systemImage:)`
  in a `Spacer()` HStack vs the watch's plain `Button("Reschedule")`).
- Design sign-off is effectively needed to pin scope (iOS-only vs both) before
  implementation.