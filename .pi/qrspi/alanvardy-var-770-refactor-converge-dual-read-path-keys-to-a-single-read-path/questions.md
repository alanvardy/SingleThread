# Research Questions

## Context

This repo is an iOS + watchOS SwiftUI app with a widget extension and a local Swift Package (`SingleThreadCore`). Settings/preferences are persisted in `UserDefaults` — some in `UserDefaults.standard`, some in a shared App Group suite (`AppGroup.defaults`). Preference values are read through several distinct mechanisms: SwiftUI `@AppStorage` bindings declared in the main app, raw `UserDefaults` API calls at various call sites, typed store types in `SingleThreadCore`, a phone→watch WatchConnectivity sync pipeline, and the widget extension. Understand how each of these read paths works and how they interact.

## Questions

1. **`@AppStorage` surface and freshness semantics** — Which properties in the app (and which targets) bind via `@AppStorage`, and to which `UserDefaults` store does each bind (`UserDefaults.standard` vs `AppGroup.defaults`)? How does SwiftUI's `@AppStorage` keep the bound value fresh — what underlying notification/observation does it rely on, and does that mechanism behave differently for a custom suite vs `.standard`? Which writes to these keys bypass `@AppStorage` entirely?

2. **Raw read sites and their execution context** — Where are the raw `UserDefaults.*` reads of preference keys, and in what execution context does each run (launch-time `AppDelegate` setup, a view-rendering computed property, a background sync/observer handler, a store's `load()` at init)? For each site, what is the timing of the read relative to when the corresponding value is written elsewhere?

3. **Core preference store types** — How are the typed store types (`Show*Preference`, `ShowUndatedRemindersPreference`, `SortOptionStore`) structured: init signature (defaults store + key), `load`/`save` semantics, and default-when-missing behavior? Where is each store type instantiated and used across the iOS app, watch app, and widget?

4. **Key-string definition and centralization** — For each `UserDefaults`-backed preference key, where is the key string declared: shared constants (e.g. `SortOption.defaultsKey`, `AppViewModel.NotificationKeys`) vs ad-hoc literals repeated at each call site? How does the WatchConnectivity sync service's own wire-key set (`PayloadKey`) relate to the store keys used locally on each target?

5. **Phone→watch preference sync** — What triggers the app to push preference changes to the watch (which observer/notification), which keys are included in the push payload, which target-side store receives each applied value, and how does the watch then read the value back (which suite, which path)? What is the direction of authority in the sync (phone → watch only, or bidirectional)?

6. **Test coverage and sandboxing** — Which tests exercise these preference keys, what `UserDefaults` sandboxing/cleanup patterns do they use (real suite + unique key + defer, fresh `UserDefaults(suiteName:)` instances, both-suite cleanup), and what do the `--ui-testing`/`--seed` launch-arg seams write into which suites?

7. **Widget read path** — How does the widget extension read these preferences when building its timeline entries, which store/suite does each read go through, and how does that interact with the app's App-Group writes?