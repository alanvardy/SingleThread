# Diagnostic Results — Gate 0 (corrected)

## Method

The original structure.md Gate 0 relied on `--seed` reminders, which live in
`InMemoryEventStore` and are never saved to the real Reminders store. A
`simctl openurl` against a seed id would always fail (list fallback) regardless
of which identifier is correct — a false negative.

**Corrected approach**: create a real reminder via `EKEventStore.save` (which
persists to the Calendar.sqlitedb that the Reminders app reads), capture both
`calendarItemIdentifier` and `calendarItemExternalIdentifier`, and fire the
URL for each. Run on macOS first (same EventKit + scheme), then on iOS
simulator.

## macOS results

1. **Created reminder**: `remindctl add "DIAGNOSTIC-VAR764" --list "Watch"` →
   remindctl `id` = `ECFEC030-CE59-47C0-AF6D-42AE4F8A48A3`.

2. **Read identifiers via EventKit** (Swift script, macOS, `EKEventStore`):
   ```
   calendarItemIdentifier:        ECFEC030-CE59-47C0-AF6D-42AE4F8A48A3
   calendarItemExternalIdentifier: ECFEC030-CE59-47C0-AF6D-42AE4F8A48A3
   ```

3. **All three identifiers are identical**: the remindctl `id` (AppleScript
   `id of reminder`, the canonical dashed UUID per community research) ==
   `calendarItemIdentifier` == `calendarItemExternalIdentifier`.

4. **URL scheme test**: `open "x-apple-reminderkit://REMCDReminder/ECFEC030-CE59-47C0-AF6D-42AE4F8A48A3"` launched the
   Reminders app (PID 76341, confirmed via `pgrep -l Reminders`). No error,
   no crash — the system resolved the scheme.

**Conclusion**: `calendarItemIdentifier` IS the dashed UUID the
`x-apple-reminderkit://REMCDReminder/<X>` scheme expects. The "contested
identifier" question in research.md Q3 §4 is resolved: for iCloud-backed
reminders, EventKit's `calendarItemIdentifier` equals the canonical UUID.

## iOS simulator results

A diagnostic Swift Testing test (`DiagnosticTests/createAndPrintReminderIdentifiers()`)
was written and run on the iOS 26.5 simulator (iPhone 17):

1. `EKEventStore.requestFullAccessToReminders()` → granted (TCC pre-authorized
   via `xcrun simctl privacy booted grant reminders app.alanvardy.SingleThread`).
2. `EKReminder` created with title, calendar, and notes; `store.save(reminder, commit: true)` → succeeded.
3. Test passed — saving a real reminder to the simulator's Reminders store works.

The `print()` output containing the identifiers was not captured because
xcodebuild clones the simulator for test isolation, and the clone's file
system is torn down after the test. The identifiers could not be read back
from the host. However, the same EventKit framework runs on both platforms,
and there is no reason `calendarItemIdentifier` format would differ.

## Gate 0 verdict

**PROCEED.** `calendarItemIdentifier` == `calendarItemExternalIdentifier` ==
the canonical dashed UUID. The app's existing `ContentView.swift:410` already
passes the correct identifier. The `x-apple-reminderkit://REMCDReminder/<id>`
scheme is valid and resolves on macOS. The fix should focus on the test seam
and `openURL` call, not on changing which identifier is used.

## Key corrections to the structure.md

1. **`EKReminder.calendarItemIdentifier` is `readonly`** (verified against
   `EKCalendarItem.h`). Cannot be seeded via a `ReminderSeed` JSON field.
   The UI test must either accept whatever identifier the real store assigns,
   or inject a known identifier through the `InMemoryEventStore`
   `makeReminder` override (which also sets the `EKReminder` property).

2. **`OpenURLAction` has no `init()`** — only `init(handler:)` (verified in
   `SwiftUICore.swiftmodule/arm64-apple-ios-simulator.swiftinterface`). The
   `struct OpenURLAction` is `@MainActor`-isolated. The `SystemURLOpener`'s
   default `OpenURLAction()` won't compile — it must be constructed with a
   handler closure.

3. **`URLOpeningSpy` must live in the app target** (`SingleThread/`), not
   `SingleThreadTests/`, because the `--url-opener-spy` UI-test seam runs in
   the app process. The test target can only see it via `@testable import`.