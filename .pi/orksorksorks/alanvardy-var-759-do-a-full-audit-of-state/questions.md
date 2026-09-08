# Research Questions

## Context

The SingleThread codebase spans four targets — an iOS app (`SingleThread/`), a
watchOS app (`SingleThreadWatch/`), a widget extension (`SingleThreadWidget/`),
and a shared SPM package (`SingleThreadCore/Sources/SingleThreadCore/`) — with
state held in two UserDefaults suites (an App Group and `.standard`),
`@Observable`/`ObservableObject` view-model stores, transient view-local
`@State`, and cross-process WatchConnectivity payloads. Research should focus
on mapping where state lives, how each value is read and written, and how
values relate to one another within and across targets.

## Questions

1. **Persisted-state inventory**: What UserDefaults keys exist, across both the
   App Group suite (`group.app.alanvardy.SingleThread`) and `.standard`? For
   each key: where is it declared, what default value applies when absent (and
   how is that encoded — `object(forKey:) as? Bool` vs `bool(forKey:)` vs
   registerDefaults), which targets read vs. write it, and are there keys with
   multiple read paths (e.g. `@AppStorage` plus raw reads, as with
   `enableActionButtons`, `notificationsEnabled`/`notificationIntervalHours`,
   and `allowsLandscape`)? How does the `AppGroup.defaults` fallback to
   `.standard` behave, and which keys would share a namespace when the suite is
   unregistered (as on watchOS, previews, and fresh simulators)?

2. **In-memory observable stores**: What mutable properties do the
   `@Observable` / `ObservableObject` classes hold — `ReminderStore`,
   `EntitlementStore`, `EntitlementState`, `CompletionGlow`, `UndoStore`, the
   app/watch composition view models, `SettingsBindings`, `ResumptionGate`, and
   the dictation / background-image stores? Which properties are transient vs.
   mirrored from persisted state, and where does one logical value exist in
   more than one store (e.g. sort option, show-* display flags, entitlement)
   with copies that could diverge? Which of these classes are
   `@Observable`/`ObservableObject` vs. plain value types, and which expose
   private mutable state only through methods?

3. **Multi-way and combinatorial state clusters**: Identify groups of boolean
   flags or state fields that jointly describe a single phenomenon — the
   completion-transition states (glow active, ghost card, completion buffer),
   the empty / all-done / first-card display branches, entitlement resolution
   and gating (`isEntitled`, `isEnabled`, `hasResolvedEntitlement`,
   `canMutate`, including the exact freemium completion-count cap boundary `< 100`
   vs `<= 100`), and dictation recording vs. UI state. For each cluster: what
   value combinations are possible or unreachable, which combinations are
   contradictory, and what does the app render/do under each combination?

4. **Existing enum-based state patterns**: Which multi-way states are already
   modeled as enums (`SortOption`, `AppearanceMode`, `TextSize`, the widget's
   `NextThingEntry.State`, `CreationFeedback`, `ReminderPriority.Level`), and
   how are they persisted and loaded (rawValue round-trips, fallbacks on
   unrecognized values, CaseIterable)? Which multi-way states remain bare
   Bools, Ints, or optionals (e.g. `BackgroundFade` percent constants, paired
   show/hide toggles, the watch ghost-card transition flags)? What conventions
   do the enum-based implementations share (single defaultsKey, store wrapper,
   presentation extensions)?

5. **Cross-process and cross-target sync state**: Which values flow over
   WatchConnectivity in `SkippedReminderSyncService` — the exact payload keys,
   latest-wins semantics of `pushAll()`, replace-not-union receive behavior,
   and per-key receive hooks — and which of those are double-persisted on the
   watch? Note the phone wires App-Group-backed stores into the service while
   the watch injects `.standard`-backed stores — where else does that
   divergence matter? How do the `PendingCompletionStore` relay safety valve
   (300 s expiry, prune-on-reload) and the shared `completionCount` counter
   (incremented by phone, written by watch, hardcoded cap of 100) work, and how
   does the widget extension read and mutate state in its own process
   (preferences, sort, intents)?

6. **State mutation surface and change propagation**: For key persistent values
   (e.g. `sortOption`, `showUndatedReminders`, `completionCount`), enumerate
   every call site across all targets that writes or mutates them. How does
   change detection propagate — `@AppStorage` + `.onChange` chains,
   `withObservationTracking`, `UserDefaults.didChangeNotification` (including
   the `lastShow*` shadow copies on `AppViewModel`), and the closure hooks on
   `ReminderStore` — and which write paths bypass the shared hooks (e.g. direct
   property assignment vs. `setSortOption()` vs. test-seam `set(_:forKey:)`
   writes)?

7. **Test seams intersecting production state**: What launch-arg-driven and
   test-only state exists (`--ui-testing-*`, `--seed`, `loadsReminders:`,
   `isGlowUITesting`, `settingsBag`, `pendingSummary`/`lastScheduleSummary`,
   the 23-key persisted reset list in `UITestingSeed`)? Which production keys
   do the seams read or write, and could the seams leave the app in a state
   that production code paths would never produce?