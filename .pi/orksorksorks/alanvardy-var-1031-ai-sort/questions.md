# Research Questions

## Context

The SingleThread iOS codebase manages a reminder list that can be ordered by
several sort options chosen in a settings sheet; ordering is computed in the
core package and the resulting order is consumed by iOS, watch, and widget
views. A separate dictation feature accepts freeform audio and parses it into
structured reminders. This research maps the sort pipeline end to end, the
settings-sheet UI state model, any on-device intelligence facilities already
present, freeform-text entry precedents, and the test seams that exercise
ordering.

## Questions

1. Trace how a sort option flows through the app end-to-end: where the
   sort-option enum and its store live, how the picker saves a selection,
   how the ordering comparator applies that selection to the visible
   reminder list, and how the selection propagates to the watch and widget
   consumers.

2. What on-device AI / ML / intelligence facilities does this app or its
   linked platform SDKs currently use or reference? Examine the
   SFSpeechRecognizer dictation path (including requiresOnDeviceRecognition)
   and search for any other Apple intelligence APIs (Foundation Models,
   SiriKit, Core ML, on-device model assets, local LLM clients) referenced
   anywhere in the repo or its project manifests. Report exactly what
   exists, with file:line.

3. What patterns exist anywhere in the app targets (iOS, watch, widget) or
   core for entering or importing freeform user text — text fields, editors,
   dictation insertion, or freeform fields in test seed payloads? Where does
   freeform text enter the app today, and in what form is it parsed or
   stored?

4. How is the Filter & Sort settings sheet (and comparable @AppStorage-bound
   settings sheets) constructed, and how does the app retain UI state across
   that sheet being closed and reopened, or across picker selection changes?
   What mechanism binds controls to persisted values, and how is control
   visibility currently toggled based on related selections, if at all?

5. How does ReminderStore compute the visible-reminders ordering, and which
   tests cover ordering and sort-option changes? Which harnesses exist to
   construct a deterministic reminder list for testing ordering — the
   --seed JSON schema and InMemoryEventStore, --ui-testing, and any watch or
   widget test setups — and how are they wired?

6. How does the dictation path turn freeform input into structured reminder
   data: the ReminderDictationParser and its callers in SingleThreadCore,
   and what parsing/validation helpers does core provide for interpreting
   user-authored text?