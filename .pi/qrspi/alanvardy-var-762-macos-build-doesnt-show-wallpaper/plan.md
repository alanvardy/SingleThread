# Implementation Plan

## Overview

Make the macOS build render the background photo behind the reminder card, matching iOS: un-gate `BackgroundPhotoLayer` from its `#if os(iOS)` block into one cross-platform view with a per-expression `Data → Image?` bridge, then un-gate its instantiation in `ContentView`.

No store/fetch/prefs/settings changes — those are already shared and CI-green on macOS. Work is a two-stage vertical of pure render layers: Stage 1 is a behavior-neutral refactor with new headless tests; Stage 2 is a compile-level integration verified by build + existing suites + manual visual check.

---

## Phase 1: Cross-platform image bridge + view refactor

Delivers one `BackgroundPhotoLayer` definition instead of an iOS-only block, with the platform split reduced to a single testable `Data → Image?` bridge. Green tests prove the bridge decodes a valid JPEG and rejects garbage on **both** platforms, and that the struct still constructs with valid/nil data. On iOS this stage is a no-op (identical rendering path).

### Changes

#### 1. Imports — make `SwiftUI` unconditional
**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

`BackgroundPhotoLayer` now compiles on macOS, so `SwiftUI` (for `View`, `Image`, `Color`, `.overlay`, `.ignoresSafeArea`, etc.) must be imported on both platforms. UIKit/AppKit stay per-expression.

**Replace** (current lines 1–8):

```swift
import Foundation
#if os(iOS)
    import SwiftUI
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import OSLog
```

**With**:

```swift
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import OSLog
```

#### 2. Un-gate `struct BackgroundPhotoLayer` + add `image(from:)` bridge
**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

**Replace** the whole `#if os(iOS)` … `#endif` block at the bottom of the file (current lines 260–289):

```swift
#if os(iOS)
    /// Decorative full-bleed background photo layer shown behind the reminder
    /// list. Non-interactive and hidden from accessibility so it never steals
    /// touches or pollutes the a11y tree.
    struct BackgroundPhotoLayer: View {
        let imageData: Data?
        /// Toggled from Settings; `false` hides the photo without touching disk.
        var isEnabled = true
        /// Fade level as a SwiftUI opacity fraction, chosen in Settings.
        var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

        var body: some View {
            if isEnabled, let image = imageData.flatMap(UIImage.init(data:)) {
                // The overlay wrapper pins the layer to its parent's size so
                // `scaledToFill` can never expand the surrounding layout.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .ignoresSafeArea()
                    .opacity(opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
#endif
```

**With** (one struct, no `#else` copy; bridge replaces the inline `UIImage.init(data:)` + `Image(uiImage:)`):

```swift
/// Decorative full-bleed background photo layer shown behind the reminder
/// list. Non-interactive and hidden from accessibility so it never steals
/// touches or pollutes the a11y tree.
struct BackgroundPhotoLayer: View {
    let imageData: Data?
    /// Toggled from Settings; `false` hides the photo without touching disk.
    var isEnabled = true
    /// Fade level as a SwiftUI opacity fraction, chosen in Settings.
    var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

    var body: some View {
        if isEnabled, let image = imageData.flatMap(Self.image(from:)) {
            // The overlay wrapper pins the layer to its parent's size so
            // `scaledToFill` can never expand the surrounding layout.
            Color.clear
                .overlay {
                    image
                        .resizable()
                        .scaledToFill()
                }
                .ignoresSafeArea()
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// `nil` when `data` isn't a decodable image on this platform.
    static func image(from data: Data) -> Image? {
        #if os(macOS)
            NSImage(data: data).map(Image.init(nsImage:))
        #else
            UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}
```

Note: `Self.image(from:)` is `(Data) -> Image?`, which is exactly `Optional<Data>.flatMap`'s transform shape — `imageData.flatMap(Self.image(from:))` yields `Image?`.

#### 3. New headless unit tests
**File**: `SingleThreadTests/BackgroundPhotoLayerTests.swift`
**Action**: create

Ungated (runs on iOS **and** macOS). Xcode auto-discovers new files (synchronized file groups) — no pbxproj edit.

```swift
import Foundation
@testable import SingleThread
import Testing

// MARK: - BackgroundPhotoLayer Tests

@MainActor
struct BackgroundPhotoLayerTests {
    @Test
    func imageFromValidJPEGDataIsNonNil() {
        #expect(BackgroundPhotoLayer.image(from: BackgroundTestFixtures.jpegData) != nil)
    }

    @Test
    func imageFromInvalidDataIsNil() {
        #expect(BackgroundPhotoLayer.image(from: Data("not an image".utf8)) == nil)
    }

    @Test
    func constructsWithValidAndNilData() {
        let valid = BackgroundPhotoLayer(
            imageData: BackgroundTestFixtures.jpegData,
            isEnabled: true,
            opacity: 1)
        #expect(valid.isEnabled)
        #expect(valid.imageData == BackgroundTestFixtures.jpegData)

        let nilData = BackgroundPhotoLayer(imageData: nil)
        #expect(nilData.imageData == nil)

        let disabled = BackgroundPhotoLayer(
            imageData: BackgroundTestFixtures.jpegData,
            isEnabled: false,
            opacity: BackgroundFade.opacity(for: BackgroundFade.defaultValue))
        #expect(!disabled.isEnabled)
    }
}
```

- `@MainActor`: the app target enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so `BackgroundPhotoLayer` and its static `image(from:)` / memberwise init default to `@MainActor`; the test target does not, so the suite annotates explicitly (same pattern as `BackgroundFadeTests` / `BackgroundImageStoreTests`).
- Reuses `BackgroundTestFixtures.jpegData` (1×1 valid JPEG) already in the test bundle.

### Verification

#### Automated
- [x] `make format` then `make lint` — SwiftFormat (`--lint`) + SwiftLint (`--strict`) clean on the new test file and modified sources
- [x] `make test` — iOS unit suite green (new `BackgroundPhotoLayerTests` pass on iOS)
- [x] `make mac-test` — macOS unit suite (`-only-testing:SingleThreadTests`) green; proves the bridge compiles and passes on macOS
- [x] `make periphery` — Periphery `--strict` clean (struct still live on iOS via the still-gated `ContentView` instantiation)

#### Manual
- [ ] iOS simulator (optional): photo still renders behind the card identically to before — this stage is behavior-neutral on iOS

---

## Phase 2: Render integration (un-gate `ContentView`)

Makes the photo layer unconditional in the root `ZStack` so macOS actually renders it. The `if isEnabled, let image` guard inside the view already handles the no-cached-photo case, so a fresh macOS install still shows just the system background. No signature or logic change.

### Changes

#### 1. Remove the `#if os(iOS)` around the `BackgroundPhotoLayer(...)` instantiation
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**Replace** (current lines 148–155):

```swift
            Color.systemBackground.ignoresSafeArea()
            #if os(iOS)
                BackgroundPhotoLayer(
                    imageData: viewModel.backgroundImage.imageData,
                    isEnabled: backgroundEnabled,
                    opacity: BackgroundFade.opacity(for: backgroundFadePercent))
            #endif
            if viewModel.store.loadsReminders {
```

**With**:

```swift
            Color.systemBackground.ignoresSafeArea()
            BackgroundPhotoLayer(
                imageData: viewModel.backgroundImage.imageData,
                isEnabled: backgroundEnabled,
                opacity: BackgroundFade.opacity(for: backgroundFadePercent))
            if viewModel.store.loadsReminders {
```

ZStack order unchanged: `Color.systemBackground` → photo layer → content (`ContentView.swift:146-160`).

### Verification

#### Automated
- [ ] `make mac-build` — proves the ungated instantiation compiles on macOS
- [ ] `make mac-test` — macOS unit suite green (`BackgroundImageStoreTests`/`BackgroundFadeTests`/`ColorCrossPlatformTests` + new `BackgroundPhotoLayerTests`)
- [ ] `make test` — iOS unit suite green (confirms the iOS render path is untouched)

#### Manual
- [ ] `make mac-run` — macOS app launches and the photo renders **behind** the reminder card (not over it)
- [ ] Fade `Picker` (Settings → Background) changes the photo opacity visibly
- [ ] Pin toggle keeps the current photo (skip refresh) across relaunch
- [ ] Disabling the background `Toggle` hides the photo (returns to `Color.systemBackground`)
- [ ] Fresh/no-cached-photo state shows only the system background (no crash, no layout shift)
- [ ] Photo does not render in a visually broken way behind the titlebar / traffic-light buttons (Open Risk 1) — document the result in the PR, following `BackgroundCardTests.swift`'s "rendered look verified manually" pattern

---

## Cross-Cutting Notes

- **Render "look" is un-stubbable below the top layer** — no headless pixel assertion; the `image(from:)` bridge is the testable unit (Phase 1) and pixel-level verification is deferred to the manual check in Phase 2.
- **Deployment target already satisfied** — `scripts/test.sh` pins `MACOSX_DEPLOYMENT_TARGET = 26.5` (≥ macOS 11 required by `Image(nsImage:)`); no action needed.
- **No macOS UI-test harness** — `--ui-testing` stays iOS-compiled; verification remains unit tests + manual smoke.
- **New test file needs no pbxproj edit** — Xcode synchronized file groups auto-discover it.

## Testing Checkpoints

Advance only when each gate below is green; on failure stop and fix before the next stage.

1. **Phase 1 done** → `make test`, `make mac-test`, `make lint`, `make periphery` all green.
2. **Phase 2 done** → `make mac-build` + `make mac-test` + `make test` green, and the manual macOS visual check passes.
3. **Final (once, by parent)** → `./scripts/test.sh` full gate green (format, lint, build, Periphery, iOS unit + UI, watch unit + UI, macOS unit).
