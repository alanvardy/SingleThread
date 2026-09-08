# Research Questions

## Context

Focus on how the background photograph changes over time, how that behavior is
driven and surfaced from the Settings screen, and how background state is
persisted and tested. Read `SingleThread/BackgroundImageStore.swift`,
`SingleThread/BackgroundSettingsView.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/SettingsBindings.swift`, `SingleThread/ContentView.swift`,
`SingleThread/AppViewModel.swift`, `SingleThreadCore` preference stores, and
`SingleThreadTests` / `SingleThreadUITests` as starting points.

## Questions

1. Trace every path that can replace the currently-displayed photo in
   `SingleThread/BackgroundImageStore.swift`. How do `refreshIfNeeded(maxAge:)`
   and `forceRefresh()` decide to fetch, what state do they consult (sidecar
   `fetchedAt`, the 24h `defaultMaxAge` threshold, `isRefreshing`), where are
   they triggered from (`ContentViewModel`/`ContentView`), and what happens on
   failure — does the prior photo survive?

2. How is the network and disk surface abstracted for testability and what are
   the exact fetch/persist mechanics? Describe `BackgroundImageFetching` and
   its `URLSession` conformance, the two endpoints involved, the
   `fetchAndPersist(from:)` order of operations (decode, validate as image,
   atomic write, then flip observable state), and how the sidecar metadata
   (`BackgroundMetadata`) is stored alongside the photo bytes.

3. How is the Background section of the Settings screen assembled and wired?
   Trace the `NavigationLink` row in `SingleThread/SettingsView.swift`, the
   `Form` in `SingleThread/BackgroundSettingsView.swift` (its existing
   `Toggle`, `Picker`, and refresh `Button`), how sub-views receive only the
   bindings they need from the `SettingsBindings` bag, and how the sheet's
   `.onChange(of:)` hooks write bag values back to `@AppStorage` properties in
   `SingleThread/ContentView.swift`. What does the existing toggle row
   ("Background") do that a sibling toggle would mirror?

4. How are phone-local cosmetic preferences like the background settings
   persisted and reset? Compare the `@AppStorage(key, store: .standard)`
   declarations in `ContentView.swift` (with defaults mirrored in
   `SettingsBindings`) against the `AppGroup.defaults` tier and the
   `SingleThreadCore` preference-struct pattern (`init(defaults:key:)`,
   `isEnabled`/`set`). How do `UITestingSeed.persistedKeys` and the
   `--ui-testing`/`--seed` launch seams handle resetting these keys between
   runs?

5. How are background behavior and settings UI tested today? Cover the unit
   tests (`BackgroundImageStoreTests` with injected fake client, temp
   directories, and the 1×1 JPEG fixture; `BackgroundFadeTests`;
   `SettingsViewTests` body-string assertions) and the UI tests
   (`testBackgroundToggleHidesAndPersistsAcrossRelaunch` using the `--ui-testing`
   relaunch pattern and `flipToggle`, `testBackgroundRefreshButtonExists`).
   Note which seams and fixtures exist for exercising a new row or toggle.

6. Which targets consume the background photo or its preferences? Confirm
   whether the widget (`SingleThreadWidget`), watch app (`SingleThreadWatch`),
   and macOS app reference `BackgroundImageStore`, `BackgroundPhotoLayer`, or
   the background `@AppStorage` keys, and how the App Group / sync payloads
   share (or deliberately do not share) background-related state — so any new
   background preference knows whether it must be propagated cross-target.