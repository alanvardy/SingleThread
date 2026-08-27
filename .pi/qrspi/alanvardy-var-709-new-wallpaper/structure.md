# Structure Outline

## Approach

Extend `BackgroundImageStore` with a 24-hour staleness default, a force-refresh
path, and a `private(set) var isRefreshing` flag; thread the observable store
through `SettingsView` → `BackgroundSettingsView` to replace frozen credit
snapshots with live reads, and add a refresh `Button` with `ProgressView`
feedback. Each layer is fully tested before the next begins.

---

## Stage 1: Store Layer — `BackgroundImageStore` extensions

Add the `defaultMaxAge` constant, give `refreshIfNeeded` a default parameter,
add `forceRefresh()` and `isRefreshing`. This is the bottom-most layer: pure
data-access + freshness-policy logic, testable in isolation against
`FakeBackgroundFetcher` + temp directories.

**Files**: `SingleThread/BackgroundImageStore.swift`,
`SingleThreadTests/BackgroundImageStoreTests.swift`

**Key changes**:

- `static let defaultMaxAge: TimeInterval = 86_400` — new constant on `BackgroundImageStore`
- `func refreshIfNeeded(maxAge: TimeInterval = Self.defaultMaxAge) async` — add default
- `private(set) var isRefreshing = false` — new observable flag
- `func forceRefresh() async` — new public method; skips `isFresh` guard, reuses the
  existing `try await client.fetchData(…) → decode → guard isDecodableImage → persist
  → flip state` pipeline, toggles `isRefreshing` around the network work
- `isRefreshing` set to `true` before fetch, `false` in a `defer` block inside
  `forceRefresh()`; `refreshIfNeeded` does **not** touch `isRefreshing` (only the
  explicit user action does)

**Tests** (all in `BackgroundImageStoreTests`):

| Test | What it proves |
|---|---|
| `forceRefreshBypassesFreshSidecar` | `forceRefresh()` hits network even when sidecar is seconds old; `requestedURLs.count` increases |
| `forceRefreshRetainsPriorImageOnFailure` | `forceRefresh()` with a failing fetch keeps `imageData`/`photographer`/`photographerURL` unchanged |
| `forceRefreshUpdatesAttributionAfterSuccess` | `photographer`/`photographerURL` reflect new payload after a successful force refresh |
| `isRefreshingToggledDuringForceRefresh` | `isRefreshing` is `true` while fetch is in-flight, `false` after (both success and failure paths) |
| `staleSidecarTriggersRefetchWith24hDefault` | 24h+1s-old sidecar → refetch; 23h-old sidecar → skip (existing test adapted to new constant) |
| `freshSidecarSkipsNetworkWith24hDefault` | existing `freshSidecarSkipsNetwork` test adapted to use the default `maxAge` |

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/BackgroundImageStoreTests` — all 12 tests green (6 existing + 6 new).

---

## Stage 2: ContentViewModel — adopt default `maxAge`

Drop the hard-coded `3600` literal so `ContentViewModel.task` relies on the
store-owned default. A one-line change that proves the default parameter wiring
works end-to-end and that no other call sites break.

**Files**: `SingleThread/ContentViewModel.swift`

**Key changes**:

- `ContentViewModel.task(showUndatedReminders:)` line 81: `await backgroundImage.refreshIfNeeded(maxAge: 3600)` → `await backgroundImage.refreshIfNeeded()`

**Tests**: no new tests needed; existing `ContentViewModel` tests + store tests remain green.

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` — all tests green.

---

## Stage 3: View threading — pass `BackgroundImageStore` to settings, add refresh button

Replace the read-only `backgroundPhotographer`/`backgroundPhotographerURL`
params with the live `@Observable BackgroundImageStore` reference, threaded
through `SettingsView` into `BackgroundSettingsView`. Add the refresh `Button`
with `ProgressView` feedback in `BackgroundSettingsView`'s `Form`. Update
previews and the `ContentView` sheet call site.

**Files**: `SingleThread/SettingsView.swift`,
`SingleThread/BackgroundSettingsView.swift`, `SingleThread/ContentView.swift`

**Key changes**:

- `SettingsView.init`:
  ```diff
  - backgroundPhotographer: String?,
  - backgroundPhotographerURL: URL?,
  + backgroundImage: BackgroundImageStore,
  ```
  Drop the two private `let backgroundPhotographer/URL` stored properties.

- `SettingsView.body` — the `NavigationLink` to `BackgroundSettingsView`:
  ```diff
  - BackgroundSettingsView(
  -     backgroundEnabled: $bindings.backgroundEnabled,
  -     backgroundFadePercent: $bindings.backgroundFadePercent,
  -     backgroundPhotographer: backgroundPhotographer,
  -     backgroundPhotographerURL: backgroundPhotographerURL)
  + BackgroundSettingsView(
  +     backgroundEnabled: $bindings.backgroundEnabled,
  +     backgroundFadePercent: $bindings.backgroundFadePercent,
  +     backgroundImage: backgroundImage)
  ```

- `BackgroundSettingsView`:
  ```diff
  - let backgroundPhotographer: String?
  - let backgroundPhotographerURL: URL?
  + var backgroundImage: BackgroundImageStore
  ```
  Attribution `Section` footer reads `backgroundImage.photographer` /
  `backgroundImage.photographerURL` live.
  New `Section` above the attribution footer containing a `Button`:
  ```swift
  Section {
      Button {
          Task { await backgroundImage.forceRefresh() }
      } label: {
          HStack {
              Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
              Spacer()
              if backgroundImage.isRefreshing {
                  ProgressView()
              }
          }
      }
      .disabled(backgroundImage.isRefreshing)
  }
  ```

- `ContentView.swift` sheet call site:
  ```diff
  - backgroundPhotographer: viewModel.backgroundImage.photographer,
  - backgroundPhotographerURL: viewModel.backgroundImage.photographerURL,
  + backgroundImage: viewModel.backgroundImage,
  ```

- All `#Preview`s in `SettingsView.swift` and `BackgroundSettingsView.swift`:
  replace the two read-only params with a `BackgroundImageStore()` instance.

**Tests**: no new unit tests (view-only wiring); existing unit + UI tests must
stay green. The `testBackgroundToggleHidesAndPersistsAcrossRelaunch` UI test
still passes (it navigates Background but doesn't tap the new button yet).

**Verify**:
1. `make build` succeeds (proves all previews compile)
2. `./scripts/test.sh` — full gate green

---

## Stage 4: UI tests — refresh button reachability

Add a UI-test assertion that the refresh button exists and is tappable in
Settings → Background. Does **not** assert the fetched image (no live network
in UI tests); only proves the control is present and interactive.

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:

- New `@MainActor func testBackgroundRefreshButtonExists()`:
  1. Launch with `--seed` (one reminder)
  2. Navigate Settings → Background
  3. Assert `app.buttons["Refresh wallpaper"].exists`
  4. Tap the button (triggers `forceRefresh()`; the real `URLSession` may hit
     the network, but the test doesn't assert the result — only that the button
     is tappable without crashing)
  5. Assert `ProgressView` appears briefly or button is hittable post-tap

- The existing `testBackgroundToggleHidesAndPersistsAcrossRelaunch` is
  unchanged.

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` — all UI tests green (existing + 1 new).

---

## Testing Checkpoints

| After Stage | Gate |
|---|---|
| 1 — Store layer | `BackgroundImageStoreTests` (12 tests) green |
| 2 — ContentViewModel adoption | `SingleThreadTests` (all) green |
| 3 — View threading | `make build` + `./scripts/test.sh` green |
| 4 — UI tests | `SingleThreadUITests` (all) green + `./scripts/test.sh` green |