# Design Discussion

## Current State

The background photo pipeline is 100% shared between iOS and macOS — fetch
(`BackgroundImageStore.refreshIfNeeded()`), persist (`Data.write(options: .atomic)`
at `BackgroundImageStore.swift:250-256`), observable store (`imageData`,
`isEnabled`, `isPinned`), and preferences (`@AppStorage` `backgroundEnabled` /
`backgroundFadePercent` / `backgroundPinned` at `ContentView.swift:86-93`). The
settings row in `SettingsView.swift:89-98` is ungated and fully wired on both
platforms.

The divergence is exactly one gate deep: the render layer. `BackgroundPhotoLayer`
(`BackgroundImageStore.swift:260-289`) is a `#if os(iOS)` whole-block view that
constructs `Image(uiImage:)` from a `UIImage`. Its instantiation in
`ContentView.swift:150-155` is inside `#if os(iOS)`. On macOS, the root `ZStack`
(`ContentView.swift:146-160`) compiles with only `Color.systemBackground` behind
the content — the photo bytes are fetched and sitting in memory, never rendered
(`research.md` Q1, Q2).

The `NSImage` bridge exists only for validation (`isDecodableImage` at
`BackgroundImageStore.swift:241-247`) — never for rendering. The cross-platform
color pattern (`Color+CrossPlatform.swift:3-20`) uses per-expression `#if os(macOS)`
guards, not whole-block or whole-file gates.

## Desired End State

The macOS build renders the background photo behind the reminder card, consistent
with iOS behavior: the photo appears when `backgroundEnabled` is true, respects
the fade opacity from `BackgroundFade.opacity(for:)` (`BackgroundFade.swift:13-24`),
and honors the pin toggle (skip refresh, keep current photo). The settings
controls (enabled/fade/pin) already work — after this change they have a visible
effect on macOS.

**Verification**: the existing macOS unit tests (`BackgroundImageStoreTests`,
`BackgroundFadeTests`, `ColorCrossPlatformTests`, `UITestingSeedTests`) continue
passing on `platform=macOS` in CI. A new unit test verifies the cross-platform
`BackgroundPhotoLayer` constructs correctly with valid and invalid `Data` on both
platforms. Visual rendering is verified manually on macOS, following the same
pattern documented in `BackgroundCardTests.swift` ("rendered look verified
manually/review, not headlessly").

## Patterns to Follow

### Use these patterns (with file:line refs)

1. **Per-expression `#if os(macOS)` for image bridging** — `isDecodableImage`
   at `BackgroundImageStore.swift:241-247` uses `#if os(iOS) UIImage(data:)`
   / `#elseif os(macOS) NSImage(data:)`. The new photo layer uses the same
   per-expression gate for the `Image(uiImage:)` / `Image(nsImage:)` call.

2. **One view definition, not two** — `Color+CrossPlatform.swift:3-20` defines
   one `static var systemBackground: Color` with per-expression branches, not
   separate iOS/macOS extensions. The refactored `BackgroundPhotoLayer` follows
   this: one `struct` with a per-expression image bridge, not a `#if os(iOS)`
   block and a separate `#if os(macOS)` block.

3. **`if let` nil-guard for the image** — the existing `BackgroundPhotoLayer`
   (`BackgroundImageStore.swift:268`) uses `if isEnabled, let image = ...` so
   the view renders nothing when there's no cached photo. Keep this pattern:
   on a fresh macOS install with no cached image, the layer is invisible.

4. **ZStack layering order** — `ContentView.swift:146-160`: color base →
   photo layer → content. Keep this order; the photo layer becomes unconditional
   (removes the `#if os(iOS)` gate) since the `if let` inside already handles
   the nil-image case.

5. **Existing test patterns for visual features** — `BackgroundCardTests.swift`
   is `#if os(iOS)` and explicitly documents "rendered look verified manually"
   (`BackgroundCardTests.swift:78`). The new unit test for the cross-platform
   layer follows the unit-test pattern of `BackgroundImageStoreTests` (which
   already runs on macOS) and documents manual visual verification.

6. **`@AppStorage(.standard)` for cosmetic preferences** — the three background
   keys (`ContentView.swift:86-93`) are `.standard`-backed, phone-local state.
   No change to this; the macOS render path reads the same keys.

### Do NOT follow these patterns

- **Whole-block `#if os(iOS)` around a view definition** (`BackgroundImageStore.swift:260-289`)
  is the pattern being removed. Replace with a single cross-platform view.
- **Separate `#if os(iOS)` / `#else` instantiation sites** — the current
  `ContentView.swift:150-155` gate is removed; the layer becomes unconditional.
- **`#if os(iOS)` for the settings row** — the Notifications row
  (`SettingsView.swift:57-66`) is hidden on macOS; the Background row is the
  anomaly (fully wired). Keep it that way — rendering is what was missing, not
  settings.
- **Adding a macOS UI test harness** — the existing `--ui-testing` single-reminder
  seam is iOS-compiled (`AppViewModel.swift:238-274`). Making it cross-platform
  is a separate project; follow the existing pattern of unit tests + manual
  visual verification.

## Design Decisions

1. **Cross-platform rendering via per-expression gate**: Refactor
   `BackgroundPhotoLayer` into a single view that uses `#if os(macOS)
   Image(nsImage:)` / `#else Image(uiImage:)` for the two-line image bridge.
   Chosen over a separate `BackgroundPhotoLayer+macOS.swift` because the
   codebase already uses per-expression gates for platform bridging
   (`isDecodableImage`, `Color.systemBackground`), and the rest of the view
   body (`.resizable().scaledToFill().ignoresSafeArea().opacity()...`) is
   identical SwiftUI. One definition = one source of truth.

2. **Unconditional instantiation in ContentView**: Remove the `#if os(iOS)`
   gate at `ContentView.swift:150-155`. The `BackgroundPhotoLayer` already
   guards on `if isEnabled, let image = ...` — when no photo is cached
   (fresh macOS install), the view renders nothing and the ZStack layout is
   unchanged. No `#else` branch needed.

3. **Settings row left ungated**: The Background row in `SettingsView` is
   already fully wired and functional on macOS. Hiding it would be a temporary
   regression; once rendering lands, the feature is complete end-to-end with
   no further settings changes.

4. **Unit tests only for macOS verification**: The existing macOS unit test
   suite (`BackgroundImageStoreTests`, `BackgroundFadeTests`,
   `ColorCrossPlatformTests`) already covers the store, fade math, and color
   bridge. A new unit test verifies `BackgroundPhotoLayer` constructs correctly
   with valid/invalid `Data` on macOS. No macOS UI test harness is built —
   the existing iOS UI tests don't assert rendering either
   (`SingleThreadUITestsFlows.swift:338-340`), and making `--ui-testing`
   cross-platform is out of scope.

5. **`.ignoresSafeArea()` kept unconditionally**: The root `Color.systemBackground`
   already uses `.ignoresSafeArea()` unconditionally (`ContentView.swift:149`)
   and works on macOS. The photo layer keeps it for consistency; on macOS it
   extends to the window edge below the titlebar, which is the desired behavior.

## What We're NOT Doing

- **Not** adding a macOS UI test harness or making `--ui-testing` cross-platform.
- **Not** changing the fetch/persist/store pipeline — it's already cross-platform.
- **Not** gating or hiding the Background settings row on macOS.
- **Not** adding `NSWindow` decoration, titlebar chrome, or `WindowGroup` modifiers.
- **Not** changing the ZStack layering order or introducing new window surfaces.
- **Not** touching the `MacAppDelegate` appearance loop — it only sets
  `NSApp.windows[].appearance` and has no interaction with the photo layer.
- **Not** introducing new cross-platform abstractions (no `CrossPlatformImage`
  type, no factory pattern) — the per-expression bridge is sufficient.

## Open Risks

1. **`ignoresSafeArea()` on macOS titlebar**: The research notes this is an
   unverified open area (`research.md` Open Areas). The root color already uses
   it unconditionally and works, but the photo layer adds a second
   `.ignoresSafeArea()` call. Manual verification on macOS is needed to confirm
   the photo doesn't render behind the traffic-light buttons or titlebar in a
   visually broken way.

2. **`NSImage(data:)` → `Image(nsImage:)` color space**: `NSImage` may interpret
   the JPEG data with a different color space than `UIImage` on iOS. The photo
   might appear slightly different on macOS. This is a cosmetic concern, not a
   correctness issue, and is verified manually.

3. **No macOS visual verification in CI**: The existing test pattern for visual
   features is manual verification (`BackgroundCardTests.swift:78`). A macOS
   rendering regression could go unnoticed between manual checks. Mitigation:
   the unit test verifies the view constructs without crashing, and the store
   tests already verify the data pipeline end-to-end on macOS.

4. **macOS 11 minimum deployment**: `Image(nsImage:)` requires macOS 11. The
   project's `MACOSX_DEPLOYMENT_TARGET` should be confirmed ≥ 11.0 (the
   existing `isDecodableImage` already uses `NSImage(data:)` and compiles, so
   this is likely satisfied).