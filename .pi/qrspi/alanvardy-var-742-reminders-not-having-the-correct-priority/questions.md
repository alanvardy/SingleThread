# Research Questions

## Context

Focus on the SingleThread codebase: the iOS app (`SingleThread/`), the watchOS
companion app (`SingleThreadWatch/`), and the shared `SingleThreadCore` SPM
package. Explore the full reminder data flow from the system EventKit store to
on-screen presentation on both platforms, the skip mechanism and its
persistence, all code paths that create reminders, the iPhone↔Watch
synchronization of state, and existing test coverage. Report what exists and
how it works with `file:line` references; do not propose changes or fixes.

## Questions

1. **Fetch path: EKReminder → in-app model.** How does `ReminderStore` load
   reminders from EventKit and map them into the app's model objects? Which
   `EKReminder` properties are read, transformed, stored, or dropped — in
   which load paths (initial load, reload, refresh, skip re-application) — and
   where is the loaded data cached or invalidated? What raw values can
   `EKReminder.priority` hold, and how are unset/none values represented?

2. **Skip mechanism end-to-end.** How does the skip gesture work — where is
   skip state persisted (key, format, storage), when is it recorded and when
   is it cleared, how does a skipped reminder later re-enter the visible list,
   and does any step re-fetch or rewrite the underlying `EKReminder` or the
   in-memory representation of a reminder?

3. **Reminder creation paths.** Which code paths create new `EKReminder`
   objects (e.g. dictation, UI-test seeding, any other user-facing creation
   flow), which properties do they set on the new object, what are the
   defaults for unset properties (including priority), and how do newly
   created reminders enter the visible list and filtering/sorting?

4. **iOS presentation of priority.** How is a reminder's priority represented
   in the iOS view model layer and rendered by the UI (markers, colors,
   ordering)? Is there any transformation between the model value and what is
   displayed, and when are the view model objects that hold priority created
   or recreated?

5. **WatchOS data acquisition and presentation.** Does the watch app fetch
   reminder data from EventKit directly or receive it from the phone? Trace
   where priority is read on the watch, how it is displayed, and what the
   completion/transition snapshot (ghost card) copies — and whether that
   snapshot is ever written back or re-fetched.

6. **iPhone↔Watch synchronization of skipped identifiers.** How are
   skipped-reminder identifiers exchanged over WatchConnectivity — which side
   pushes, which side applies, when do in-memory sets refresh (app lifecycle
   events, connectivity events), and how are conflicts or stale sets
   reconciled?

7. **Test coverage of priority and skip behavior.** Which unit and UI tests
   exercise reminder priority handling, the skip flow, and the `--seed`
   JSON / in-memory store seam? What fixtures do they use and what do they
   assert?