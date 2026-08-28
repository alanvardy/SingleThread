# Structure Outline

## Approach

Add a first-launch guide overlay to the watch app, following the existing show-*
preference + state-holder + sync-pipeline + iPhone-settings pattern. Each layer
is fully tested before the next one begins — no code lands without green tests.

---

## Stage 1: Pre ference Layer — `ShowGuidePreference`

A single-key `UserDefaults` wrapper in `SingleThreadCore` with nil→true default
(first-l aunch semantic). This is the data contract every layer above consumes.

**Files**:
- **New**: `SingleThreadCore/Sources/SingleThreadCore/ShowGuidePreference.swift`
- **New/Edit**: `SingleThreadWatchTests/ShowGuideStateTests.swift` (preference tests within)

**Key changes**:
- `public struct ShowGuidePreference` — mirrors `ShowCompletionGlowPreference`
  - `init(defaults: UserDefaults = AppGroup.defaults, key: String = "showGuide")`
  - `var isEnabled: Bool { defaults.object(forKey: key) as? Bool ?? true }` (nil→true)
  - `func set(_ enabled: Bool)`

**Tests** (in `ShowGuideStateTests.swift`):
- `isEnabled` returns `true` when key is missing (first-launch)
- `isEnabled` returns `false` after `set(false)`
- `isEnabled` returns `true` after `set(true)`
- Round-trip: `set(false)`, new instance reads `false`

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadWatchTests/ShowGuideStateTests
```

---

## Stage 2: State-Holder Layer — `ShowGuideState`

An `@Observable` holder in `SingleThreadWatch/` wrapping `ShowGuidePreference`
with `.standard` defaults (watch has no App Group). Consumed by the overlay in
Stage 5 and by the sync receive hook in Stage 3.

**Files**:
- **New**: `SingleThreadWatch/ShowGuideState.swift`
- **Edit**: `SingleThreadWatchTests/ShowGuideStateTests.swift` (add state-holder tests)

**Key changes**:
- `@Observable final class ShowGuideState` — mirrors `ShowCompletionGlowState`
  - `init()` — reads `preference.isEnabled`
  - `private(set) var isEnabled: Bool`
  - `func apply(_ value: Bool)` — persists + republishes
  - `private let preference = ShowGuidePreference(defaults: .standard)`

**Tests** (add to `ShowGuideStateTests.swift`):
- `init` reads seeded `false` from `.standard`
- `apply(false)` persists to `.standard` + republishes `isEnabled = false`
- `apply(true)` after `apply(false)` republishes correctly
- Serialized suite (shared `"showGuide"` key in `.standard`), `defer` cleanup

**Verify**: same command as Stage 1 (same test suite); all tests green before proceeding.

---

## Stage 3: Sync Pipeline Layer — Wire `showGuide` into WCSession

Add `showGuide` to the wire-protocol enum, the phone → watch push path, and the
watch receive hook. After this stage, toggling the show-* flags on the iPhone
(the existing five) still works; `showGuide` is sent but not yet settable from
the iPhone UI.

**Files**:
- **Edit**: `SingleThreadCore/Sources/SingleThreadCore/SkippedReminderSyncService.swift`
- **Edit**: `SingleThread/AppViewModel.swift`
- **Edit**: `SingleThreadWatch/WatchAppViewModel.swift`
- **Edit**: `SingleThreadWatchTests/WatchSyncPipelineTests.swift` (add guide-specific assertions)

**Key changes**:

1. `SkippedReminderSyncService`:
   - `PayloadKey.showGuide = "showGuide"` (alongside existing keys)
   - `init` param: `showGuideStore: ShowGuidePreference = ShowGuidePreference()`
   - `init` param: `sendsShowGuide: Bool = true` (default `true` — phone pushes)
   - `private let showGuideStore: ShowGuidePreference`
   - `private let sendsShowGuide: Bool`
   - `pushAll()` branch: `if sendsShowGuide { context[PayloadKey.showGuide] = showGuideStore.isEnabled }`
   - `apply(context:)` branch: `if let showGuide = context[PayloadKey.showGuide] as? Bool { showGuideStore.set(showGuide); handler?(showGuide) }`
   - `public nonisolated(unsafe) var onShowGuideReceived: ((Bool) -> Void)?`

2. `AppViewModel` (phone):
   - Add `showGuideStore: ShowGuidePreference()` to service init
   - Add `sendsShowGuide: true` (alongside existing `sendsShowDate: true`)

3. `WatchAppViewModel` (watch):
   - `let showGuideState = ShowGuideState()` (alongside five existing state holders)
   - Add `showGuideStore: ShowGuidePreference(defaults: .standard)` to service init
   - Add `sendsShowGuide: false` (alongside existing `false` flags)
   - In `wireStateReceiveHooks`: add `onShowGuideReceived` → `showGuideState.apply(value)`
   - Inject `showGuideState` into `WatchReminderViewModel` init

**Tests** (in `WatchSyncPipelineTests.swift`):
- `showGuide` key appears in push context when `sendsShowGuide: true`
- `showGuide` key absent from push context when `sendsShowGuide: false`
- Receiving `showGuide: false` fires `onShowGuideReceived` hook with `false`
- Receiving `showGuide: true` fires hook with `true`
- Verify existing show-* tests still pass (regression guard)

**Verify**:
```fish
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadWatchTests
```

---

## Stage 4: iPhone Settings Layer — "Show Guide Again" Toggle

Add the toggle to `ReminderSettingsView`, the binding prop to `SettingsBindings`,
and the write-back in `ContentView`. At this point the user can toggle "show
guide again" on iPhone → the flag reaches the watch → `ShowGuideState` updates.

**Files**:
- **Edit**: `SingleThread/SettingsBindings.swift`
- **Edit**: `SingleThread/ReminderSettingsView.swift`
- **Edit**: `SingleThread/ContentView.swift`

**Key changes**:

1. `SettingsBindings`:
   - Add `var showGuide: Bool` property
   - Add `showGuide: Bool = true` init param (default `true` = guide shown on first launch)

2. `ReminderSettingsView`:
   - Add `@Binding var showGuide: Bool` param
   - Add Toggle: `Tooggle(isOn: $showGuide) { Label("Show guide again", systemImage: "questionmark.circle") }`
   - No `.onChange(of: showGuide)` → no widget reload needed (design decision)

3. `ContentView`:
   - `makeSettingsBag()`: add `showGuide: showGuide` to both `#if os(iOS)` and `#else` branches
   - `.sheet` write-back chain: add `.onChange(of: bag.showGuide) { _, new in showGuide = new }`
   - Add `@AppStorage("showGuide") private var showGuide = true` (matches nil→true default)

**Tests**: No new unit tests (pure wiring; the sync-pipeline tests from Stage 3 prove
the phone→watch path). Manual verification:
1. Build to iPhone 17 simulator
2. Open Settings → Reminder → toggleshow guide again off
3. Confirm watch `ShowGuideState.isEnabled` becomes `false` (via sync pipeline test or debug)

**Verify**: `./scripts/test.sh` passes for all existing targets; manual toggle smoke test.

---

## Stage 5: Watch UI Overlay Layer — `GuideOverlay`

The visual guide overlay on the watch card: instructional text + two arrows +
"Got it" button. Dismissed when button tapped (writes `showGuidePreference.set(false)`
via `ShowGuideState.apply(false)`).

**Files**:
- **New**: `SingleThreadWatch/GuideOverlay.swift`
- **Edit**: `SingleThreadWatch/WatchReminderView.swift`
- **Edit**: `SingleThreadWatch/WatchReminderViewModel.swift` (if injection needed; TBD)
- **New/Edit**: `SingleThreadWatchTests/GuideOverlayStateTests.swift` (or add to existing suite)
- **Edit**: `SingleThreadWatchUITests/` (new UI test + accessibility audit)

**Key changes**:

1. `GuideOverlay` (new view):
   - `struct GuideOverlay: View`
   - Props: `isActive: Bool`, `onDissmiss: () -> Void`, `reduceMotion: Bool`
   - Content: `VStack` with:
     - `Text("Tap Complete to finish")` + arrow pointing down-left toward Complete button
     - `Text("Tap Skip to skip")` + arrow pointing down-right toward Skip button
     - `Button("Got it") { onDissmiss() }` — `.buttonStyle(.borderedProminent)`
   - Animation: `.transition(.opacity)` + `.animation(reduceMotion ? nil : .easeInOut(0.4), value: isActive)`
   - Accessibility: `.accessibilityAddTraits(.isButton)` on "Got it"; `.accessibilityLabel` on instructions
   - Appearance: semi-translucent background (`.ultraThinMaterial` or `.black.opacity(0.7)`) + white text
   - Full-screen: `.ignoresSafeArea()` + `.allowsHitTesting(isActive)`
   - Arrows: `Image(systemName: "arrow.down.left")` / `"arrow.down.right"`, positioned via `.frame(alignment:)` or `ViewThatFits`

2. `WatchReminderView`:
   - Add `showGuideState: ShowGuideState` (or read from `viewModel` if injected there)
   - Add `.overlay { if showGuideState.isEnabled { GuideOverlay(...) } }` on `reminderContent` ZStack
   - The overlay must NOT cover the authorization-gate paths (`.notDetermined` / access-denied) — only `reminderContent`
   - On dismiss: `showGuideState.apply(false)` — persists immediately

3. `WatchReminderViewModel` (if state holder is routed through VM):
   - Add `let showGuideState: ShowGuideState` param
   - Expose for view consumption

**Tests**:

- **Unit tests** (`SingleThreadWatchTests/`):
  - `GuideOverlay` view snapshot: overlay renders when `isActive: true`, does not render when `false`
  - Dismiss calls `onDissmiss` closure
  - Accessibility: "Got it" button has `.isButton` trait
  - Reduce Motion: `.animation(nil, value:)` when `reduceMotion: true`

- **UI tests** (`SingleThreadWatchUITests/`):
  - `testGuideAppearsOnFirstLauch()`: launch with `--reset-guide` (see Stage 6), assert guide overlay is visible, tap "Got it", assert overlay dismissed and reminder card visible
  - `testGuideDoesNotReapearOnSubsequentLauch()`: launch without `--reset-guide` (guide already dismissed in previous run), assert guide is NOT visible
  - `testAccessibilityAudit()`: run `app.pperformAccessibilityAudit(for: [. . .])` with guide visible — ensure no a11y violations
  - `testGuideReappearsAfterPhoneResets()`: sync `showGuide: true` context → assert overlay reappears

**Verify**:
```fish
# Unit tests
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadWatchTests

# UI tests (includes accessibility audit)
xcodebuild test -scheme SingleThread \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SingleThreadWatchUITests
```

---

## Stage 6: Testing Seam — `--reset-guide` Launch Arg

Add a `--reset-guide` flag to `WatchAppViewModel.init` that removes the
`"showGuide"` key from `.standard` before building the store. This is the
watch-equivalent of the iOS `--reset-glow-preference` pattern.

**Files**:
- **Edit**: `SingleThreadWatch/WatchAppViewModel.swift`

**Key changes**:
- In `init(arguments:)`, before building state holders:
  ```swift
  if arguments.contains("--reset-guide") {
      UserDefaults.standard.removeObject(forKey: "showGuide")
  }
  ```
- Follows the iOS `--reset-glow-preference` pattern (`AppViewModel.swift:186-190`)

**Tests**: Covered by Stage 5 UI tests (they use `--reset-guide` to force first-launch state).

**Verify**: Stage 5 UI tests pass; manual check that `--reset-guide` launch makes the guide appear on next cold start.

---

## Testing Checkpoints

| Stage | Gate — must be green before advancing |
|-------|--------|
| 1 | `SingleThreadWatchTests/ShowGuideStateTests` — preference read/wite/round-trip |
| 2 | Same suite — add state-holder tests, all green |
| 3 | `SingleThreadWatchTests` (both suites) — sync pipeline tests + regression |
| 4 | `./scripts/test.sh` — full gate; manual toggle smoke test on iPhone sim |
| 5 | `SingleThreadWatchTests` + `SingleThreadWatchUITests` — overlay unit + UI + a11y audit |
| 6 | Stage 5 UI tests (they depend on `--reset-guide`) |

---

## Cross-Cutting Notes

- **The authorization-gate paths** (`.notDetermined` / access-denied in `WatchReminderView.swift:40-57`) must NOT show the guide overlay. The overlay is scoped to `reminderContent` only (Stage 5). No special gating needed — the ZStack overlay is not in the gate branches.
- **VoiceOver focus management** (open risk from design): When the overlay appears, VoiceOver focus should land on the guide text or "Got it" button. If `.accessibilityFocused` is needed on watchOS, this is a Stage 5 implementation detail — the a11y audit UI test will catch regressions.
- **`showList`/`showCompletionGlow` are the closest precedents** for a preference that has no widget-reload side effect — `showGuide` follows the same pattern (no `.onChange(of: showGuide)` → `showPreferenceChanged()` call).