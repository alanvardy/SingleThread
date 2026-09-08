# Design Discussion — Fetch Fresh Wallpaper on Demand (var-709)

## Current State

The background photograph is a phone-local cosmetic feature owned end-to-end by
`BackgroundImageStore` (`SingleThread/BackgroundImageStore.swift`), a
`@MainActor @Observable` class created once in `AppViewModel.init`
(`AppViewModel.swift:76`) and never touching the App Group or sync payloads
(`AppViewModel.swift:23-26`).

**Fetch / persist / serve** — `refreshIfNeeded(maxAge:)`
(`BackgroundImageStore.swift:88-109`) loads whatever is on disk, then
short-circuits the network when the sidecar is still fresh; only a
missing/corrupt/stale sidecar triggers a fetch. The fetch is two sequential
`fetchData` calls (metadata JSON from `https://vardy.cc/unsplash`, then the photo
bytes from `payload.url`), guarded by `isDecodableImage` (`:96`). Persistence
writes both `background.jpg` and the `background.json` sidecar atomically, disk
before observable state (`:99-103`); on any error it logs and keeps prior state
(`:107-109`). Staleness is `Date().timeIntervalSince(metadata.fetchedAt) < maxAge`
against the ISO-8601 sidecar timestamp (`:142-150`).

**Network** — `BackgroundImageFetching` (`:11-15`) is a one-method protocol so
tests inject a fake; `URLSession` conforms and adds HTTP-status validation
(`:18-26`). Non-2xx → `URLError(.badServerResponse)`; undecodable JSON → decode
throw; non-image bytes → `URLError(.cannotDecodeContentData)` (`:96`).

**State flow & `maxAge`** — `ContentViewModel.task` is the *only* caller of
`refreshIfNeeded`, passing a hard-coded `maxAge: 3600`
(`ContentViewModel.swift:81`). The layer is rendered in `ContentView`'s `ZStack`
via `BackgroundPhotoLayer(imageData:isEnabled:opacity:)` (`ContentView.swift:52-58`),
fed from `viewModel.backgroundImage.imageData` and the two `@AppStorage`
preferences (`backgroundEnabled`, `backgroundFadePercent`, `ContentView.swift:158-162`).

**Settings surface** — `SettingsView` presents a `List` of `NavigationLink`s
(`SettingsView.swift:34-84`); the Background row opens `BackgroundSettingsView`
(`:72-79`) with the bag-derived bindings plus read-only `photographer`/`URL`
snapshotted at sheet-open time (`ContentView.swift:113-114`).
`BackgroundSettingsView` is a `Form` holding a `Toggle`, a `Picker` over
`BackgroundFade.allValues`, and a `Section {} footer` attribution `Link`
(`BackgroundSettingsView.swift:16-35`).

**Testing seams** — unit tests inject `FakeBackgroundFetcher` + a UUID temp
directory (`BackgroundImageStoreTests.swift:161-207`); a 1×1 JPEG fixture passes
the image gate (`:174-186`). iOS UI tests seed reminders via `--seed` /
`InMemoryEventStore` (`AppViewModel.swift:113-167`) and use `--ui-testing` for
relaunch persistence (`SingleThreadUITestsFlows.swift:163-193`). There is **no**
launch-arg seam that swaps the background network client.

## Desired End State

1. **24-hour staleness** — a stored wallpaper is considered fresh for 24 hours
   (up from 1 hour), so the network is not hit on every cold launch.
2. **On-demand refresh** — a control in the Background settings screen that
   *always* fetches a fresh wallpaper from the Unsplash endpoint, regardless of
   current staleness, updating the on-screen photo and its attribution.
3. **No regression to existing behavior** — refresh failures still keep the
   prior image (never blank), the photo+credit pair invariant still holds, and
   the toggle/fade controls are unchanged.

**Verification:**
- Unit: force refresh bypasses the fresh guard; a 24h-old sidecar still skips
  the network while a 24h+ε one refetches; failure keeps prior image; the
  photo↔credit pairing invariant holds after force refresh.
- UI: the refresh control is reachable and tappable from Settings → Background;
  the attribution section still renders.
- Manual/review: visual confirmation that a fresh photo paints (headless tests
  cannot assert actual rendering — `ContentView.swift:64` seam comment).

## Patterns to Follow

- **Store owns persistence + freshness policy.** Extend `BackgroundImageStore`
  with the new method and the `maxAge` default, keeping the "disk first, then
  flip observable state; on error keep prior state" convention
  (`BackgroundImageStore.swift:99-109`). This is the established MVVM posture
  post `var-697`: `AppViewModel` is the composition root, `ContentViewModel`
  forwards mutations, the view stays declarative.
- **Settings controls live inside the sub-view `Form`.** Add the new control to
  `BackgroundSettingsView`'s `Form` (`BackgroundSettingsView.swift:16-35`),
  matching the existing `Toggle`/`Picker` placement, rather than adding a new
  `NavigationLink` row to `SettingsView`'s `List`.
- **Sub-views take only what they need.** `BackgroundSettingsView` currently
  takes bindings + read-only credit values (`:4-6`); it will take the observable
  store instead of the frozen credit snapshot, so the credit updates reactively
  (consistent with how `SettingsView` already passes `viewModel.backgroundImage.*`).
- **Observable state, not closures.** `BackgroundImageStore` is already
  `@Observable`; pass it down and read `store.photographer/URL` live rather than
  threading one-shot closures or duplicated read-only params.
- **Test seams for the store are real.** Reuse `FakeBackgroundFetcher` +
  temp-directory staging (`BackgroundImageStoreTests.swift:161-207`) for every
  new store behavior; add unit tests in the existing `@Suite(.serialized)`
  `@MainActor` suite.
- **`@AppStorage` four-place mirroring is NOT needed here.** The refresh action
  is not a persisted preference, so it does **not** need a `SettingsBindings`
  var, a `makeSettingsBag()` entry, a `.onChange` write-back, or a
  `@AppStorage` key (contrast `ContentView.swift:158-162, 489-511`). Do not
  follow that pattern for a non-persisted action.

## Design Decisions

1. **Control location**: a `Button` (with a `Label`, e.g. "Refresh wallpaper")
   inside `BackgroundSettingsView`'s `Form`, below the fade picker and above the
   attribution `Section` footer. Discoverable next to the other background
   controls; no change to `SettingsView`'s `List`.

2. **Threading the store**: pass the `@Observable BackgroundImageStore` into
   `BackgroundSettingsView` (via `SettingsView`), replacing the read-only
   `backgroundPhotographer`/`backgroundPhotographerURL` params. The attribution
   `Section` reads `store.photographer`/`store.photographerURL` live so it
   updates when a refresh lands, instead of staying frozen at sheet-open time.

3. **`maxAge` constant**: add `static let defaultMaxAge: TimeInterval = 86_400`
   on `BackgroundImageStore` and give `refreshIfNeeded` a default parameter of
   `Self.defaultMaxAge`. `ContentViewModel.task` drops its `3600` literal
   (`ContentViewModel.swift:81`) and relies on the default. One owner for
   freshness policy; the two call sites cannot drift.

4. **Force-refresh semantics + feedback**: add a force path that skips the
   `isFresh` guard but reuses the existing fetch/persist pipeline, keeping
   "disk first / keep prior state on error". Track `private(set) var isRefreshing`
   so the button can show a `ProgressView` and disable while in flight —
   preventing double-fetch and blank-image flash.

5. **Testing strategy**: exhaustive unit tests on the store (force bypasses
   freshness; 24h boundary; failure retains prior image; pairing invariant), and
   a UI test that asserts the refresh button exists and is tappable in
   Settings → Background **without** asserting the fetched image. No new
   launch-arg seam for the network client — that would expand scope and touch
   the composition root for marginal end-to-end coverage.

## What We're NOT Doing

- **No new network launch-arg/`--seed` seam** for `BackgroundImageFetching`; the
  store is unit-tested against a fake and UI tests only assert reachability.
- **No persistence of the last-refresh timestamp beyond the existing sidecar**
  — `fetchedAt` already drives staleness; nothing new is stored.
- **No user-facing setting for `maxAge`** — it stays a fixed, store-owned
  constant.
- **No periodic/timer-driven refresh** — refresh remains `.task`-driven at view
  appear plus the explicit button.
- **No change to `SettingsBindings`, `makeSettingsBag()`, or `@AppStorage` keys**
  — the refresh action is not a persisted preference.
- **No change to the fade/toggle controls, the attribution `Link`, or the
  `BackgroundPhotoLayer` rendering path.**
- **No watchOS/widget changes** — the background is phone-local cosmetic state.

## Open Risks

- **Live-network UI-test flakiness** — avoided by not asserting the fetched image
  in UI tests, but the button tap in a seeded UI test must not *accidentally*
  reach the real endpoint; the tap is only asserted for existence/interaction.
- **`isRefreshing` observation** — the `Button` must rebuild on the observable
  change; if `BackgroundSettingsView` is a value-type `View` without
  `@Observable` tracking, the store reference must be an `@Bindable`/observed
  property so the `ProgressView`/disabled state actually updates.
- **`SettingsView` init signature** — replacing the read-only credit params with
  the store touches `SettingsView.init` and both `#Preview`s
  (`SettingsView.swift:11-24, 102-131`); previews must be updated or they fail
  to compile.
- **`refreshIfNeeded` default-parameter source compatibility** — adding a default
  keeps `ContentViewModel.task` compiling, but verify no other call site
  (previews/tests) passes `maxAge` in a way that would break.
- **24h staleness in long-running sessions** — no timer exists, so a device left
  open for days still shows the stale photo until the view re-appears or the
  button is pressed; acceptable but worth noting.
