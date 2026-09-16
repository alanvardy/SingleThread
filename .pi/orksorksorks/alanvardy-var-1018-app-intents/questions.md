# Research Questions

## Context

Focus on the SingleThread iOS app and SingleThreadCore package (git root:
`/Users/vardy/dev/alanvardy-var-1018-app-intents`). Relevant areas: the
`ReminderStore` model and its task-operation methods, the existing App Intent
structs and how they and the widget invoke them, the app's entry point and
command/shortcut surfaces, the concurrency/isolation model for reaching the
event-store-backed model from non-foreground contexts, and the platform
framework (AppIntents on iOS 17) for intent results and menus. Work inside the
repo; one question may consult the public framework documentation.

## Questions

1. **ReminderStore task operations** — Trace `ReminderStore`'s methods for
   computing the current next task, completing it, and skipping it: from
   `visibleReminders` / `listContent` prioritization and filtering, through
   `completeCurrentReminder` / `completeReminder` and
   `skipCurrentReminder` / `skipCurrentReminderImmediately`. For each, note
   the `@MainActor` status, whether and how the save is awaited
   (`settle()` / `reload()`), and what the store returns. Also describe how
   the store represents the empty, all-done (`allSkipped`), and hidden
   (`hasHidden`) cases in `listContent`.

2. **Existing intent structure and surfacing** — Trace how App Intents are
   defined, structured, and invoked in this codebase: the
   `CompleteReminderIntent` / `SkipReminderIntent` structs in
   `ReminderIntents.swift` (lifecycle, `@MainActor` `perform()` shape,
   `title` / `isDiscoverable`, what they return), the widget's
   `Button(intent:)` usage, the app target's entry point (`SingleThreadApp`)
   and the macOS-only `appCommands` path, and whether any iOS
   Siri/Shortcuts/app-icon `AppShortcutsProvider` / `commandsAppShortcuts`
   surface exists in the app target today.

3. **ReminderStore construction and background access** — Trace how
   `ReminderStore` and its collaborators are constructed and shared, and what
   concurrency/isolation model governs reaching it from non-foreground
   contexts: the `ReminderStore` initializer (its params: `eventStore`,
   `skipStore`, `skipCountStore`, `pendingCompletionStore`, `excludeStore`,
   `loadsReminders`), the `AppViewModel` composition root and how it builds
   the store, the `@MainActor @Observable` actor isolation and the Swift 6 /
   `SWIFT_DEFAULT_ACTOR_ISOLATION` per-target project settings, and how the
   widget extension constructs a fresh `ReminderStore` outside the normal app
   lifecycle — including how EventKit authorization is handled there
   (`makeEntry`) versus the store's own `start()` / `requestAccess()` paths.

4. **AppIntents framework result and surface shapes** — What result and
   dialog shapes does the AppIntents framework (iOS 17, Swift 6) document for
   an `AppIntent.perform()`, and what does it document for exposing intents
   via the app-icon long-press / App Shortcuts and Siri? Specifically: the
   `IntentResult` variants (plain `.result()`, `.result(dialog:)`,
   `.result(value:)`, `.finished(result:)`), how `perform()` should present
   an empty / failure outcome cleanly, and the documented
   `AppShortcutsProvider` / `commandsAppShortcuts` / Siri surface for these
   intents. Consult the public AppIntents / Shortcuts framework documentation
   for this; the repo itself has no such surface yet.