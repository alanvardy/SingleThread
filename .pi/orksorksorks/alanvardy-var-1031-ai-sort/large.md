# Task

VAR-1031 "AI sort" — add an AI sort option to the reminders sort picker in the
SingleThread iOS app. When "AI" is selected, a text box appears letting the
user define the rules by which reminders are sorted; the sort is executed by
on-device AI. The rule text must not be lost when the user switches to a
different sort option — it is merely hidden, and reappears on return.

## Why LARGE

UNKNOWNS + NEW_SURFACE (+ CROSS_CUTTING, unknown ordering): "handled by the
on device ai" introduces a new technology/API with open research questions —
which on-device AI facility exists in this app's iOS/device context, whether
it's available on simulator vs real hardware, how freeform rule text maps to a
deterministic reminder ordering, and how that is tested. It also crosses the
reminders sort UI (new option + conditional rule-entry text box with
hidden-not-lost state) and a new AI integration layer, with no existing pattern
carrying the change end to end.

## Key files (initial pointers for research — the design phase must verify)

- The reminder sort surface: find the sort-option enum/picker (likely in
  `SingleThread/` — sort options UI and the model's sort order application in
  `SingleThreadCore/`).
- The sort application path used by the list views (`ReminderListView` and the
  watch app, if sort options are shared) and where a rule-based ordering would
  plug in.
- The `--seed`/`--ui-testing` seams and existing sort-option tests in
  `SingleThreadTests/`, for how a deterministic AI-sort test could be shaped.