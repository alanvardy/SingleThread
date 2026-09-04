# Research Questions

## Context

Focus on the `SingleThreadWidget` extension (`SingleThreadWidget/`) and the shared
`SingleThreadCore` package: the widget's timeline provider and SwiftUI views, the AppIntents
defined in Core, the App Group persistence layer and its cross-process consumers, and the
existing test seams in `SingleThreadTests/` / `SingleThreadUITests/`. Also cover how the
widget target is wired into the Xcode project relative to the app target — entitlements,
embedding, and concurrency build settings.

## Questions

1. **Widget provider & timeline flow** — Walk through `NextThingWidget` and its provider:
   how is the widget bundle registered, and how does the provider build placeholder /
   snapshot / timeline entries (`getTimeline`, `makeEntry`)? What is the entry state
   machine (auth status, empty vs all-done vs reminder), how are App Group preferences and
   sort options applied, and what mechanisms trigger a reload / recompute after mutable
   state changes (e.g. `Timeline.policy`, `WidgetCenter` calls from the app)?

2. **Widget view layer** — How are the widget's SwiftUI views structured for the declared
   families? Is there any conditional handling of `supportedFamilies` / container
   environment (sizing, rendering modes, color schemes), what accessibility identifiers
   and interactive elements (buttons, intents) does the current view expose, and how are
   the empty / all-done / no-access placeholder states rendered?

3. **AppIntents end-to-end** — Trace `CompleteReminderIntent` and `SkipReminderIntent`:
   where they live, how they are registered and attributed to an extension (Info.plist
   keys, build settings, widget metadata, or implicit AppIntents discovery), what
   `isDiscoverable` controls about where an intent surfaces, how `perform()` reaches the
   shared reminder store, and any process-lifetime constraints on their execution (e.g.
   why the skip path uses a synchronous write).

4. **Cross-process state sharing** — How is reminder / skipped / excluded / settings state
   shared between the app, widget, and watch? Map which components read vs write each
   persisted key in the App Group suite (`SkippedReminderStore`, `ExcludedListStore`,
   `SortOption`, `Show*Preference` wrappers, etc.), how the `SkippedReminderSyncService`
   fits in, and what happens when a mutation originates outside the main app process.

5. **Concurrency & build configuration** — What are the concurrency settings per target
   (`SWIFT_DEFAULT_ACTOR_ISOLATION` on app/watch but not widget, Swift 6 language mode,
   approachable concurrency), and how is `@MainActor` isolation currently expressed in
   widget provider and intent code? How is the widget extension embedded into the app in
   `project.pbxproj` (target, product type, synchronized groups, entitlements, iOS-only
   platform support) and what is the iOS deployment target?

6. **Testing & seams** — What unit tests cover the intents, `ReminderStore`, App Group
   stores, and seed plumbing today, and what do they assert? How do the iOS and watch UI
   tests drive state via the `--seed` / `--ui-testing` launch args and `InMemoryEventStore`,
   and is there any existing mechanism that launches or drives the widget extension process
   from a test (or only `#Preview` timelines)?