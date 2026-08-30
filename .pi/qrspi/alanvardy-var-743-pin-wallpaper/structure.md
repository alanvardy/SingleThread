# Structure Outline

## Approach

Add a "Pin wallpaper" toggle that gates auto-refresh in `BackgroundImageStore`
without blocking manual refresh. Built bottom-up: store behavior first (tested
in isolation with injected fakes), then the five-step settings pipe + UI
wiring, then UI-test infrastructure to prove cross-relaunch persistence.

---

## Stage 1: `BackgroundImageStore` Pin Gating

Delivers the core pin behavior in the store — `refreshIfNeeded` is gated,
`forceRefresh` is unaffected, and unpinning triggers a freshness check. All
three behaviors are proven with unit tests against injected fakes before any
UI work begins.

**Files**: `SingleThread/BackgroundImageStore.swift`,
`SingleThreadTests/BackgroundImageStoreTests.swift`

**Key changes**:

- `BackgroundImageStore` — new observable property:
  ```swift
  /// When true, `refreshIfNeeded` treats the wallpaper as perpetually fresh.
  /// Manual `forceRefresh` is unaffected. Set by the view layer from the
  /// `@AppStorage("backgroundPinned")` preference.
  private(set) var isPinned = false
  ```

- New mutator — handles the unpin→refresh transition:
  ```swift
  /// Updates the pin state. When transitioning from pinned → unpinned,
  /// immediately checks freshness and refetches if the photo is stale.
  func setPinned(_ pinned: Bool) async
  ```
  Implementation contract: if `pinned == false && isPinned == true`, calls
  `refreshIfNeeded()` after flipping `isPinned`. Otherwise just sets the
  property.

- `refreshIfNeeded(maxAge:)` — gate after `loadStoredImage()`:
  ```swift
  func refreshIfNeeded(maxAge: TimeInterval = BackgroundImageStore.defaultMaxAge) async {
      loadStoredImage()
      guard !isPinned else { return }          // ← new gate
      guard !isFresh(maxAge: maxAge) else { return }
      // ... existing fetch logic unchanged
  }
  ```

- `forceRefresh()` — **no change**. The existing `guard !isRefreshing else {
  return }` is the only gate; pin is never consulted.

**Tests** (add to `BackgroundImageStoreTests`):

| Test | Covers |
|---|---|
| `pinBlocksRefreshIfNeeded` | Pinned store + stale sidecar → `refreshIfNeeded` does **not** call `fetchData` |
| `forceRefreshBypassesPin` | Pinned store → `forceRefresh` calls `fetchData` for `randomEndpoint` |
| `unpinTriggersRefreshWhenStale` | Pinned store, stale sidecar → `setPinned(false)` calls `fetchData` |
| `unpinDoesNotRefreshWhenFresh` | Pinned store, fresh sidecar → `setPinned(false)` does **not** call `fetchData` |
| `unpinOnlyTriggersOnTrueToFalseTransition` | Already-unpinned → `setPinned(false)` no-ops (no fetch) |

All tests use injected `FakeBackgroundFetcher` + UUID temp directory
(reusing `makeStore(client:directory:)` from `BackgroundImageStoreTests.swift:328-335`).

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes for the new tests.

---

## Stage 2: Settings Pipe + UI Wiring

Wires `backgroundPinned` through the five-step settings pipe, adds the
toggle in `BackgroundSettingsView`, and propagates the pin value into
`BackgroundImageStore`. Depends on Stage 1 (the store must accept `setPinned`).

**Files**: `SingleThread/ContentView.swift`, `SingleThread/SettingsBindings.swift`,
`SingleThread/BackgroundSettingsView.swift`, `SingleThreadTests/SettingsViewTests.swift`

**Key changes**:

1. **`ContentView.swift`** — new `@AppStorage` (alongside `backgroundEnabled` at :165-166):
   ```swift
   @AppStorage("backgroundPinned", store: .standard)
   private var backgroundPinned = false
   ```

2. **`ContentView.swift`** — propagate pin to store in `.task` + `.onChange`:
   ```swift
   // In .task (before refreshIfNeeded, which is gated on isPinned):
   viewModel.backgroundImage.setPinned(backgroundPinned)
   await viewModel.task(showUndatedReminders: showUndatedReminders)

   // New .onChange:
   .onChange(of: backgroundPinned) { _, newValue in
       Task { await viewModel.backgroundImage.setPinned(newValue) }
   }
   ```

3. **`ContentView.swift`** — write-back in settings sheet (alongside :129-130):
   ```swift
   .onChange(of: bag.backgroundPinned) { _, new in backgroundPinned = new }
   ```

4. **`ContentView.swift`** — `makeSettingsBag()` both branches (iOS :545-546,
   macOS :559-560), add parameter:
   ```swift
   backgroundPinned: backgroundPinned,
   ```

5. **`SettingsBindings.swift`** — new `var` + init param (alongside
   `backgroundFadePercent` :27, :60):
   ```swift
   // init param (default false):
   backgroundPinned: Bool = false,

   // var:
   var backgroundPinned: Bool
   ```

6. **`BackgroundSettingsView.swift`** — new `@Binding` + `Section` containing
   `Toggle`, visible only when `backgroundEnabled`:
   ```swift
   @Binding var backgroundPinned: Bool

   // In body, after the Background Fade Picker, before the Refresh button:
   if backgroundEnabled {
       Section {
           Toggle(isOn: $backgroundPinned) {
               Label("Pin wallpaper", systemImage: "pin")
           }
       }
   }
   ```

7. **`SettingsView.swift`** — forward the binding (alongside :76-80):
   ```swift
   BackgroundSettingsView(
       backgroundEnabled: $bindings.backgroundEnabled,
       backgroundFadePercent: $bindings.backgroundFadePercent,
       backgroundPinned: $bindings.backgroundPinned,
       backgroundImage: backgroundImage)
   ```

**Tests**:

- `SettingsViewTests` — add `backgroundSettingsViewContainsPinToggle`:
  constructs `BackgroundSettingsView` with `.constant(true)` for
  `backgroundEnabled` and a seeded store; asserts body string contains
  `"Pin wallpaper"`.
- `SettingsViewTests` — add `pinToggleHiddenWhenBackgroundDisabled`:
  `.constant(false)` for `backgroundEnabled`; asserts body string does
  **not** contain `"Pin wallpaper"`.
- Update existing `backgroundSettingsViewContainsExpectedRows` (:115-129)
  to include `"Pin wallpaper"` in its assertion list (since `backgroundEnabled`
  is `.constant(true)` in that test, the toggle will be visible).

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes for all SettingsViewTests + BackgroundImageStoreTests.

---

## Stage 3: UI Test Infrastructure + Cross-Relaunch Test

Fixes the `persistedKeys` gap (adds the missing `backgroundFadePercent` and
the new `backgroundPinned`), then adds a UI test proving the pin toggle
persists across app relaunch. Depends on Stage 2 (the toggle must exist in UI).

**Files**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`,
`SingleThreadUITests/SingleThreadUITestsFlows.swift`

**Key changes**:

1. **`UITestingSeed.swift`** — add two keys to `persistedKeys` (:56-75):
   ```swift
   "backgroundPinned",
   "backgroundFadePercent",
   ```
   `backgroundFadePercent` is a pre-existing gap (survives `--seed` wipes
   today); fixing it alongside the new key avoids a second `persistedKeys`
   churn.

2. **`SingleThreadUITestsFlows.swift`** — new test:
   ```swift
   func testPinWallpaperTogglePersistsAcrossRelaunch()
   ```
   Pattern: mirrors `testBackgroundToggleHidesAndPersistsAcrossRelaunch`
   (:198-232):
   - Launch with `--seed` (wipes all keys, pin defaults to `false`)
   - Navigate Settings → Background
   - Assert `app.switches["Pin wallpaper"].value == "0"`
   - `flipToggle(toggle, target: "1")`
   - Back-navigate → Done → `terminate()`
   - Relaunch with `["--ui-testing"]` (avoids `resetPersistedState()` wipe)
   - Navigate Settings → Background
   - Assert `app.switches["Pin wallpaper"].value == "1"`

   Additional sanity check: flip back to `"0"`, terminate, `--ui-testing`
   relaunch, assert `"0"` — proving it's not a one-way latch.

**Verify**: `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes for the new test.

---

## Testing Checkpoints

After each stage, the following must be green before advancing:

| Stage | Command | Must Pass |
|---|---|---|
| 1 | `xcodebuild test … -only-testing:SingleThreadTests` | All `BackgroundImageStoreTests` (12 existing + 5 new) |
| 2 | `xcodebuild test … -only-testing:SingleThreadTests` | All `BackgroundImageStoreTests` + all `SettingsViewTests` (including new pin toggle assertions) |
| 3 | `xcodebuild test … -only-testing:SingleThreadUITests` | `testPinWallpaperTogglePersistsAcrossRelaunch` |
| Final | `./scripts/test.sh` | Full gate: format, lint, build, Periphery, unit tests, UI tests |