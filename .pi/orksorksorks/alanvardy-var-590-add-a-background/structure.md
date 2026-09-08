# Structure Outline

## Approach

Introduce an app-target `BackgroundImageStore` (`@MainActor @Observable`) behind a
network-client protocol seam: it fetches JSON metadata + JPEG from
`https://vardy.cc/unsplash`, persists bytes to
`Application Support/SingleThread/background.jpg` plus a sidecar metadata JSON,
and re-renders stored bytes in a new full-bleed ZStack layer at 50% opacity.
Settings gains a hide-only toggle (`backgroundEnabled`, `.standard`, default ON)
and a photographer-attribution footer fed from the same sidecar metadata.

---

## Phase 1: Fetch, persist, and render

Delivers the core end-to-end slice: app launches → store fetches photo (two-step:
JSON, then image) → validates and writes to disk → image renders behind the list.
Until first success, screen looks exactly as today.

**Files**: `SingleThread/BackgroundImageStore.swift` (new),
`SingleThread/ContentView.swift`, `SingleThreadTests/BackgroundImageStoreTests.swift` (new)

**Key changes**:
- `protocol BackgroundImageFetching: AnyObject { func data(from: URL) async throws -> Data }` — new seam;
  `extension URLSession: BackgroundImageFetching {}` as production default
- `@MainActor @Observable final class BackgroundImageStore` — new type:
  - `init(client: BackgroundImageFetching = URLSession.shared, directory: URL = defaultAppSupportDir)`
  - `private(set) var imageData: Data?`, `private(set) var photographer: String?`
  - `func refreshIfNeeded(maxAge: TimeInterval) async` — sidecar-fetched-at check;
    write-to-disk **before** flipping observable state; catch → Logger, keep prior
- `ContentView`: new ZStack child between `Color.systemBackground` and content —
  `Image(uiImage:).resizable().scaledToFill().ignoresSafeArea().opacity(0.5)` when
  `imageData != nil`; convenience init gains `backgroundImage: BackgroundImageStore`
  (default = production store); `.task` calls `await backgroundImage.refreshIfNeeded(maxAge: 3600)`
  alongside `store.start()`

**Verify**: `xcodebuild test -only-testing:SingleThreadTests` passes — fake-client
tests cover: successful fetch stores bytes + metadata, non-2xx/non-image payload
rejected, failed fetch retains prior image, stale sidecar triggers refetch,
fresh sidecar skips network. Then `./scripts/test.sh`; manually launch on
iPhone 17 sim: photo fades in over systemBackground in light and dark mode.

---

## Phase 2: Settings "Background" toggle

Delivers user control end-to-end: Toggle in Settings hides/shows the rendered
photo without touching disk data; re-enabling restores instantly.

**Files**: `SingleThread/ContentView.swift`, `SingleThread/SettingsView.swift`,
`SingleThread/UITestingSeed.swift`, `SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:
- `@AppStorage("backgroundEnabled", store: .standard) private var backgroundEnabled = true` in ContentView
- Image layer becomes conditional: `if backgroundEnabled, let imageData`
- `SettingsView.init` gains `backgroundEnabled: Binding<Bool>` (iOS and macOS inits);
  new Toggle row following the `showMicrophoneButton` precedent
- `UITestingSeed.resetPersistedState()` removes `"backgroundEnabled"` from `.standard`

**Verify**: unit tests still pass (`UITestingSeedTests` updated for the new key);
UI test launches seeded app, opens Settings, flips toggle off/on, asserts sheet
interaction succeeds and state persists across relaunch. Manual: toggle off →
plain background returns; toggle on → photo restored without refetch.

---

## Phase 3: Attribution footer

Delivers the Unsplash credit end-to-end: main Settings Form footer reads
"Photo by {photographer} on Unsplash" from stored metadata; empty while no photo.

**Files**: `SingleThread/SettingsView.swift`, `SingleThread/ContentView.swift`,
`SingleThreadTests/BackgroundImageStoreTests.swift` (footer-state cases)

**Key changes**:
- `SettingsView.init` gains `backgroundPhotographer: String?` (or derived from the
  store binding); footer Section on the main Form using the
  `Section {} footer: { Text(…) }` precedent from `ExcludedProjectsView`
- Credit text always reflects the *stored* photo because both come from one
  sidecar write

**Verify**: unit tests assert photographer/metadata pairing after fetch and
cleared metadata when no valid sidecar exists; full `./scripts/test.sh` green.
Manual: footer visible after fetch, matches photographer of displayed photo,
absent on fresh install before first success.

---

## Testing Checkpoints

After each phase, these should hold — useful for resuming after context resets:

- **Phase 1**: Unit suite green with fake network client (success / rejection /
  retention / staleness paths); app renders stored photo at 50% opacity full-bleed
  in both appearances; no photo on first-ever launch until fetch completes silently.
  Disk layout exists: `Application Support/SingleThread/background.jpg` + sidecar.
- **Phase 2**: Toggle hides/restores photo instantly; disk files untouched when
  off; `backgroundEnabled` reset by `resetPersistedState()`; UI test exercises the flow.
- **Phase 3**: Footer matches stored metadata exactly; absent when no photo;
  full CI-equivalent gate (`./scripts/test.sh`) green including Periphery and
  accessibility audit on both iPhone and iPad sims.

No unsliceable elements found — watch/widget are explicitly out of scope
(no App Group or sync changes anywhere in this feature).
