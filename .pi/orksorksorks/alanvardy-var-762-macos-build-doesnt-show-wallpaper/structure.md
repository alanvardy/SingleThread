# Structure Outline

## Approach

Make the background photo render on macOS by removing the one gate that diverges:
refactor the iOS-only whole-block `BackgroundPhotoLayer` into a single
cross-platform view with a per-expression image bridge, then un-gate its
instantiation in `ContentView`. No store/fetch/prefs/settings changes — those
are already shared and tested.

**Foundation (already green, not a stage).** The horizontal stack's bottom
layers already exist and are CI-green on `platform=macOS` — no schema, data,
or persistence work is needed. Every new stage stands on these proven layers:

- *Store/persistence*: `BackgroundImageStore` (`refreshIfNeeded`, `forceRefresh`,
  `setPinned`, `loadStoredImage`) — `SingleThread/BackgroundImageStore.swift`,
  covered by `SingleThreadTests/BackgroundImageStoreTests.swift` (24 tests, ungated).
- *Fade math*: `BackgroundFade.opacity(for:) -> Double` — `SingleThread/BackgroundFade.swift`,
  covered by `BackgroundFadeTests` (ungated).
- *Color bridge*: `Color.systemBackground` — `SingleThread/Color+CrossPlatform.swift`,
  covered by `ColorCrossPlatformTests` (ungated).
- *Preferences*: `@AppStorage` `backgroundEnabled`/`backgroundFadePercent`/
  `backgroundPinned` (`ContentView.swift:86-93`, `.standard`, ungated).

The new work is a two-stage vertical of pure render layers. Stage 1 is a
behavior-neutral refactor with new headless tests; Stage 2 is a compile-level
integration whose correctness is verified by build + the existing suites +
manual visual check (rendering can't be pixel-asserted headlessly — same
pattern documented in `BackgroundCardTests.swift:78`).

---

## Stage 1: Cross-platform image bridge + view refactor

Delivers one `BackgroundPhotoLayer` definition instead of an iOS-only block,
with the platform split reduced to a single testable `Data → Image?` bridge.
Green tests prove the bridge decodes a valid JPEG and rejects garbage on **both**
platforms, and that the struct still constructs with valid/nil data. On iOS this
stage is a no-op (identical rendering path), so it can land on its own.

**Files**:
- `SingleThread/BackgroundImageStore.swift` — refactor + imports
- `SingleThreadTests/BackgroundPhotoLayerTests.swift` — new

**Key changes**:
- Imports: `import SwiftUI` becomes unconditional (today gated `#if os(iOS)`
  at `:3-8`); UIKit/AppKit stay per-expression.
- Remove the `#if os(iOS)` … `#endif` around `struct BackgroundPhotoLayer`
  (`:260-289`) — one struct, no `#else` copy.
- Add the testable seam:
  ```swift
  struct BackgroundPhotoLayer: View {
      let imageData: Data?
      var isEnabled = true
      var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

      var body: some View {
          if isEnabled, let image = imageData.flatMap(Self.image(from:)) {
              Color.clear
                  .overlay { image.resizable().scaledToFill() }
                  .ignoresSafeArea()
                  .opacity(opacity)
                  .allowsHitTesting(false)
                  .accessibilityHidden(true)
          }
      }

      /// nil when `data` isn't a decodable image on this platform.
      static func image(from data: Data) -> Image? {
          #if os(macOS)
              NSImage(data: data).map(Image.init(nsImage:))
          #else
              UIImage(data: data).map(Image.init(uiImage:))
          #endif
      }
  }
  ```
  (Replaces the inline `imageData.flatMap(UIImage.init(data:))` + `Image(uiImage:)`.)

**Tests** (new, ungated — run on iOS *and* macOS):
- `imageFromValidJPEGDataIsNonNil` — `BackgroundPhotoLayer.image(from: BackgroundTestFixtures.jpegData) != nil` (happy path).
- `imageFromInvalidDataIsNil` — garbage `Data` → `nil` (sad path).
- `constructsWithValidAndNilData` — memberwise init builds with valid JPEG, `nil` data, and `isEnabled: false`; compile-time regression guard against re-gating the struct per platform.

**Verify**:
- `make test` (iOS unit suite) — green.
- `make mac-test` (macOS unit suite, `-only-testing:SingleThreadTests`) — green; proves the bridge compiles and passes on macOS.
- `make lint` and `make periphery` — SwiftLint `--strict` + Periphery `--strict` clean (struct still live on iOS via the still-gated `ContentView` instantiation).

---

## Stage 2: Render integration (un-gate `ContentView`)

Makes the photo layer unconditional in the root `ZStack` so macOS actually
renders it. The `if isEnabled, let image` guard inside the view already handles
the no-cached-photo case, so a fresh macOS install still shows just the system
background. No signature or logic change — this is the only stage that can't be
covered by new headless tests (SwiftUI body, compile-level).

**Files**:
- `SingleThread/ContentView.swift`

**Key changes**:
- Remove the `#if os(iOS)` / `#endif` around the `BackgroundPhotoLayer(...)`
  instantiation (`:150-155`). The call becomes unconditional:
  ```swift
  BackgroundPhotoLayer(
      imageData: viewModel.backgroundImage.imageData,
      isEnabled: backgroundEnabled,
      opacity: BackgroundFade.opacity(for: backgroundFadePercent))
  ```
- ZStack order unchanged: `Color.systemBackground` → photo layer → content
  (`ContentView.swift:146-160`).

**Tests**: no new tests — compile-level. Existing suites are the regression
guard: iOS unit + UI tests confirm the iOS path is untouched;
`BackgroundImageStoreTests`/`BackgroundFadeTests`/`ColorCrossPlatformTests`
stay green on macOS.

**Verify**:
- `make mac-build` — proves the ungated instantiation compiles on macOS.
- `make mac-test` and `make test` — both unit suites green.
- Manual: `make mac-run` → confirm photo renders behind the card, fade `Picker`
  changes opacity, pin toggle keeps the current photo, and the photo does not
  break behind the titlebar/traffic-light area (Open Risk 1). Document in the
  PR, following `BackgroundCardTests.swift`'s "rendered look verified manually".

---

## Cross-Cutting Notes

- **Render "look" is un-stubbable below the top layer.** No headless assertion
  can check pixels; the design handles this by making the `image(from:)` bridge
  the testable unit (Stage 1) and deferring pixel-level verification to the
  manual check in Stage 2 — identical to the existing `BackgroundCardTests`
  pattern. The macOS `ignoresSafeArea`/titlebar behavior (Open Risk 1) is
  likewise manual-only and is not stubbed earlier.
- **Deployment target (Open Risk 4) is already satisfied** — `scripts/test.sh`
  pins `MACOSX_DEPLOYMENT_TARGET = 26.5` (≥ macOS 11 required by
  `Image(nsImage:)`); no action needed.
- **No macOS UI-test harness** (design "NOT doing"): `--ui-testing` stays
  iOS-compiled; verification remains unit tests + manual smoke.

## Testing Checkpoints

After each incremental gate below is green, advance; if it fails, stop and fix
before the next stage.

1. **Stage 1 done** → `make test`, `make mac-test`, `make lint`, `make periphery` all green.
2. **Stage 2 done** → `make mac-build` + `make mac-test` + `make test` green, and the manual macOS visual check passes.
3. **Final (once, by parent)** → `./scripts/test.sh` full gate green (format, lint, build, Periphery, iOS unit + UI, watch unit + UI, macOS unit).
