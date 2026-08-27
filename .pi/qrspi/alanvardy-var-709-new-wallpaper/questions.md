# Research Questions

## Context

Focus on how the background photograph is fetched, persisted, and surfaced to
the UI, plus how the Settings screen is structured and how background behavior
is tested. Read `SingleThread/BackgroundImageStore.swift`,
`SingleThread/BackgroundSettingsView.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/ContentViewModel.swift`, `SingleThread/AppViewModel.swift`, and
`SingleThread/SettingsBindings.swift` as starting points.

## Questions

1. Trace the fetch/persist/serve flow in `SingleThread/BackgroundImageStore.swift`.
   How does `refreshIfNeeded(maxAge:)` decide whether to hit the network, what
   gets persisted (photo bytes plus sidecar metadata), and how is staleness
   computed from the sidecar?

2. How are network requests made and validated? Describe the
   `BackgroundImageFetching` protocol, the endpoint URL that supplies the
   photo, and how non-2xx responses and undecodable/non-image payloads are
   handled.

3. How does background state flow from creation
   (`SingleThread/AppViewModel.swift`) through `ContentViewModel` to the view
   layers (`ContentViewModel.swift`, `ContentView.swift`, `BackgroundPhotoLayer`),
   and where is the staleness `maxAge` value configured?

4. How is the Settings screen assembled (`SingleThread/SettingsView.swift`,
   `SingleThread/SettingsBindings.swift`) and how do its subviews (in particular
   `SingleThread/BackgroundSettingsView.swift`) expose controls such as toggles,
   pickers, and links — and how would a new row/action in that view fit the
   existing pattern?

5. What testing seams exist for background behavior? Describe the injected fake
   network client, staging temp directories, the photo/metadata fixtures, the
   unit tests, and how iOS UI tests seed state (`--seed`/`InMemoryEventStore`).