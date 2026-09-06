# Implementation Plan

## Overview

Suppress macOS's platform-default bezel with a centralized `.singleThreadButton()`
modifier (`.buttonStyle(.borderless)`) and give the macOS bottom-bar cluster the
same `.controlPlate()` adaptive-mono treatment iOS already uses — verified
headlessly via reflection "string-snapshot" unit tests plus a `make mac-build`
manual visual pass.

---

## Notes on deviations from `structure.md` (read first)

I expanded the structure against the actual SwiftUI reflection output and found
three places where the structure's test assertions are not implementable as
written. All three preserve the design's *intent* exactly (centralized,
assertable chrome suppression); only the asserted strings change. Evidence was
gathered by compiling/reflecting the real view shapes (see the per-stage notes).

1. **The borderless style name does not reflect through a custom `ViewModifier`.**
   `String(describing:)` of `Button("Done") {}.singleThreadButton()` prints
   `ModifiedContent<Button<Text>, SingleThreadButtonModifier>` — the modifier
   name appears, but `"BorderlessButtonStyle"` does **not** (SwiftUI reflects the
   modifier *wrapper* type, not the `.buttonStyle(...)` applied inside its
   `body`). The structure's "happy" asserts of `"BorderlessButtonStyle"` therefore
   cannot pass. The corrected, still-assertable pin is the wrapper token
   `SingleThreadButtonModifier`. (Verified: an inline `.buttonStyle(.borderless)`
   reflects `PrimitiveButtonStyleContainerModifier<BorderlessButtonStyle>`, but our
   style lives inside `modifier(SingleThreadButtonModifier())`, which does not.)

2. **The macOS cluster's `.tint(.green/.orange/.red)` never produced
   `"style: green"`/`"orange"`/`"red"` in reflection.** Those `"style: …"` strings
   come from `.swipeActions` in `ReminderCardView` (which still exist on macOS and
   still emit `"style: orange"`/`"style: green"` — so asserting their absence over
   the whole `ContentView.body` would fail). A plain `.tint(.green)` reflects as
   `_EnvironmentKeyWritingModifier<Optional<Color>>` with an opaque color value
   (no color-name string). The corrected sad-pin asserts the cluster controls no
   longer carry `_EnvironmentKeyWritingModifier<Optional<Color>>`.

3. **Consequence of (2): the cluster controls must be reflected individually.**
   The remaining white `.tint(.white)` on `ReminderCardView`'s nudge/prompt would
   otherwise confound a whole-body "no tint" assertion. The three macOS cluster
   computed vars plus `macActionMenu` therefore change `private var` → `var`
   (internal), mirroring the existing in-file `skipButton`/`actionMenuRescheduleSheet`
   precedent, so tests can reflect `view.macCompleteButton` etc. directly. This is a
   one-word visibility change on lines we are already editing.

No other deviations. Phase order, file set, and the `.borderless` design decision
are unchanged from `structure.md`/`design.md`.

---

## Stage 1: Shared chrome-suppression modifier (foundation)

### Changes

#### 1. New shared modifier
**File**: `SingleThread/SingleThreadButtonModifier.swift`
**Action**: create

```swift
import SwiftUI

/// Suppresses the platform-default button chrome so icon-only controls render
/// as their own drawn plate (`controlPlate`) without macOS's bordered bezel.
///
/// iOS/iPadOS already render icon-only labels chrome-less, so `.borderless` is
/// a no-op there; on macOS it removes the translucent square the default bezel
/// draws around a `.controlPlate()` label. Deliberately no `#if os` inside so
/// the shared (cross-platform) mic button can call the same symbol.
struct SingleThreadButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderless)
    }
}

extension View {
    /// Applies `.buttonStyle(.borderless)` through one shared symbol so the
    /// chrome-suppression decision lives in a single, reflection-assertable
    /// place (mirrors `View.controlPlate(fill:glyph:)`).
    func singleThreadButton() -> some View {
        modifier(SingleThreadButtonModifier())
    }
}
```

Xcode auto-discovers new `.swift` files (`objectVersion = 77`); no pbxproj edit.

#### 2. New reflection tests
**File**: `SingleThreadTests/SingleThreadButtonModifierTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct SingleThreadButtonModifierTests {
    /// The shared modifier is the single decision point for chrome suppression.
    /// Reflection asserts the wrapper is wired (the `.buttonStyle` it applies
    /// inside `body` is not itself reflected — see plan "Notes on deviations").
    @Test
    func composedViewCarriesSingleThreadButtonModifier() {
        let view = Button("Done") {}
            .singleThreadButton()
        #expect(String(describing: view).contains("SingleThreadButtonModifier"))
    }

    /// The modifier is opt-in: a button routed to the platform `.bordered`
    /// style (the scoped-out text-button case) must not pick it up.
    @Test
    func unmodifiedBorderedButtonDoesNotCarrySingleThreadButtonModifier() {
        let description = String(describing: Button("Done") {}.buttonStyle(.bordered))
        #expect(description.contains("BorderedButtonStyle"))
        #expect(!description.contains("SingleThreadButtonModifier"))
    }
}
```

### Verification
#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/SingleThreadButtonModifierTests` passes (macOS binary)
- [x] `make test` passes (iOS unit binary runs the same suite)
- [x] `make lint` clean

#### Manual
- [ ] None beyond the above — the modifier is not wired to any control yet.

---

## Stage 2: Standalone macOS-facing icon buttons

Applies the proven modifier to settings gear, macOS refresh, and the shared mic.

### Changes

#### 1. Settings gear, refresh, mic in `ContentView.swift`
**File**: `SingleThread/ContentView.swift`
**Action**: modify (three small insertions — add `.singleThreadButton()` after each button's `label:` closure)

Gear (the `.overlay(alignment: .topTrailing)` button):

```swift
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .controlPlate()
                    .contentShape(Rectangle())
            }
            .singleThreadButton()
            .accessibilityLabel("Settings")
```

Refresh (the `#if os(macOS)` `.overlay(alignment: .topLeading)` button) — insert before `.disabled`:

```swift
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .controlPlate()
            }
            .singleThreadButton()
            .disabled(viewModel.isRefreshing)
```

Mic (`private var micButton`, shared across platforms):

```swift
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .controlPlate()
        }
        .singleThreadButton()
        .accessibilityLabel("Dictate reminder")
```

#### 2. Update the pinned macOS refresh signature
**File**: `SingleThreadTests/SingleThreadTests.swift` (`contentViewBodyContainsRefreshButtonOnMacOS`)
**Action**: modify — the `SingleThreadButtonModifier` now sits between the `Button`'s label and the `.disabled` transform. (Derived from the live reflected type; the `_EnvironmentKeyWritingModifier<Optional<Font>>` is the `.font(.title3)`.)

Replace the `refreshButtonSignature` literal with:

```swift
            let refreshButtonSignature =
                "Button<ModifiedContent<ModifiedContent<Image, _EnvironmentKeyWritingModifier<Optional<Font>>>, "
                    + "ControlPlateModifier>>, SingleThreadButtonModifier>, "
                    + "_EnvironmentKeyTransformModifier<Bool>>, AccessibilityAttachmentModifier"
            #expect(description.contains(refreshButtonSignature))
```

#### 3. New macOS-gated reflection tests (gear + mic + scope boundary)
**File**: `SingleThreadTests/SingleThreadTests.swift`
**Action**: modify — add three `@Test`s to `struct SingleThreadTests`, each guarded by `#if os(macOS)` in its assertions (same shape as the existing refresh test).

```swift
    @Test
    func contentViewBodyContainsBorderlessSettingsGearOnMacOS() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        let description = String(describing: view.body)
        #if os(macOS)
            // The gear's label is Image.font(.title3).controlPlate().contentShape(Rectangle()),
            // wrapped by `.singleThreadButton()` then `.accessibilityLabel`. The
            // `_ContentShapeModifier<Rectangle>` distinguishes it from the refresh
            // button (which uses `.disabled` instead).
            let gearSignature =
                "Button<ModifiedContent<ModifiedContent<ModifiedContent<Image, "
                    + "_EnvironmentKeyWritingModifier<Optional<Font>>>, ControlPlateModifier>, "
                    + "_ContentShapeModifier<Rectangle>>>, SingleThreadButtonModifier>, "
                    + "AccessibilityAttachmentModifier"
            #expect(description.contains(gearSignature))
        #endif
    }

    @Test
    func contentViewBodyContainsBorderlessDictateButtonOnMacOS() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        let description = String(describing: view.body)
        #if os(macOS)
            // The mic button (shared across platforms) keeps `.title2` + `.controlPlate()`,
            // wrapped by `.singleThreadButton()` directly before `.accessibilityLabel`. No
            // `.disabled`/`.contentShape`, so `SingleThreadButtonModifier>, Accessibility…`
            // (no intervening transform) is unique to the mic.
            let micSignature =
                "Button<ModifiedContent<ModifiedContent<Image, _EnvironmentKeyWritingModifier<Optional<Font>>>, "
                    + "ControlPlateModifier>>, SingleThreadButtonModifier>, AccessibilityAttachmentModifier"
            #expect(description.contains(micSignature))
        #endif
    }

    @Test
    func rescheduleSheetTextButtonsKeepNativeChrome() {
        let view = ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
        // Scope boundary: the sheet's text "Cancel" button stays native and is
        // never routed through the new modifier.
        let sheetDescription = String(describing: view.actionMenuRescheduleSheet)
        #expect(sheetDescription.contains("Cancel"))
        #expect(!sheetDescription.contains("SingleThreadButtonModifier"))
    }
```

> The mic's shared `.singleThreadButton()` also affects iOS (no-op visually), so
> `make test` must stay green after this stage.

### Verification
#### Automated
- [x] `make mac-test` passes (updated signature + new macOS-gated asserts) — macOS suite: 2 pre-existing EntitlementStore SKTestSession tests fail on this machine (storekitd env issue, CI mac-tests green; tracked for Stage 4)
- [x] `make test` passes (shared mic `.borderless` does not break iOS)
- [x] `make format` clean, then `make lint` clean

#### Manual
- [ ] No visual check yet — Stage 4 covers the rendered result.

---

## Stage 3: macOS bottom-bar cluster parity

Transforms the `#if os(macOS)` cluster to the iOS treatment: drop tints, add
`.controlPlate()` to each label, route `Button`s through `.singleThreadButton()`,
and the `Menu` through `.menuStyle(.borderlessButton)`.

### Changes

#### 1. Cluster buttons + action menu
**File**: `SingleThread/ContentView+ActionMenu.swift` (`macCompleteButton`, `macActionMenu`, `macSkipButton`, `macDeleteButton`)
**Action**: modify — for each control: change `private var` → `var` (internal, so tests can reflect it), remove the `.tint`, add `.controlPlate()` to the label, and add `.singleThreadButton()` (buttons) / `.menuStyle(.borderlessButton)` (menu).

`macCompleteButton`:

```swift
        var macCompleteButton: some View {
            Button {
                Task { await viewModel.completeCurrentReminder() }
            } label: {
                Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .controlPlate()
            }
            .singleThreadButton()
            .keyboardShortcut("c", modifiers: [])
            .accessibilityLabel(SharedStrings.completeReminderAccessibility)
            .accessibilityIdentifier("completeButton")
            .accessibilityAddTraits(.isButton)
        }
```

`macActionMenu` (a `Menu` — no `.buttonStyle`; `.menuStyle(.borderlessButton)` + `.controlPlate()` on the label):

```swift
        var macActionMenu: some View {
            Menu {
                Button(SharedStrings.skipAction) {
                    viewModel.skipCurrentReminder()
                }
                Button("Reschedule") {
                    isShowingRescheduleSheet = true
                }
                Button(SharedStrings.deleteAction, role: .destructive) {
                    Task { await viewModel.deleteCurrentReminder() }
                }
                .keyboardShortcut(.delete, modifiers: [])
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .controlPlate()
            }
            .menuStyle(.borderlessButton)
            .keyboardShortcut("s", modifiers: [])
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
        }
```

`macSkipButton` (same pattern, `skipAction` / `circle.slash`):

```swift
        var macSkipButton: some View {
            Button {
                viewModel.skipCurrentReminder()
            } label: {
                Label(SharedStrings.skipAction, systemImage: "circle.slash")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .controlPlate()
            }
            .singleThreadButton()
            .keyboardShortcut("s", modifiers: [])
            .accessibilityLabel(SharedStrings.skipReminderAccessibility)
            .accessibilityIdentifier("skipButton")
            .accessibilityAddTraits(.isButton)
        }
```

`macDeleteButton`:

```swift
        var macDeleteButton: some View {
            Button {
                Task { await viewModel.deleteCurrentReminder() }
            } label: {
                Label(SharedStrings.deleteAction, systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .controlPlate()
            }
            .singleThreadButton()
            .accessibilityLabel(SharedStrings.deleteReminderAccessibility)
            .accessibilityIdentifier("deleteButton")
            .accessibilityAddTraits(.isButton)
        }
```

#### 2. New macOS-gated reflection tests
**File**: `SingleThreadTests/MacOSActionButtonChromeTests.swift`
**Action**: create (whole-file `#if os(macOS)`)

```swift
@testable import SingleThread
@testable import SingleThreadCore
import SwiftUI
import Testing

#if os(macOS)

@MainActor
struct MacOSActionButtonChromeTests {
    @Test
    func actionClusterButtonsUseControlPlateAndBorderlessChrome() {
        let view = makeContentView()
        #expect(String(describing: view.macCompleteButton).contains("SingleThreadButtonModifier"))
        #expect(String(describing: view.macCompleteButton).contains("ControlPlateModifier"))
        #expect(String(describing: view.macSkipButton).contains("SingleThreadButtonModifier"))
        #expect(String(describing: view.macSkipButton).contains("ControlPlateModifier"))
        #expect(String(describing: view.macDeleteButton).contains("SingleThreadButtonModifier"))
        #expect(String(describing: view.macDeleteButton).contains("ControlPlateModifier"))
    }

    @Test
    func actionMenuUsesBorderlessMenuStyleAndControlPlate() {
        let description = String(describing: makeContentView().macActionMenu)
        #expect(description.contains("BorderlessButtonMenuStyle"))
        #expect(description.contains("ControlPlateModifier"))
    }

    @Test
    func actionClusterDoesNotTintItsButtons() {
        // `.tint` reflects as _EnvironmentKeyWritingModifier<Optional<Color>>;
        // `.controlPlate` resolves its own fill from colorScheme, so the removed
        // green/orange/red tints must leave no Color writer behind.
        let tintMarker = "_EnvironmentKeyWritingModifier<Optional<Color>>"
        let view = makeContentView()
        #expect(!String(describing: view.macCompleteButton).contains(tintMarker))
        #expect(!String(describing: view.macActionMenu).contains(tintMarker))
        #expect(!String(describing: view.macSkipButton).contains(tintMarker))
        #expect(!String(describing: view.macDeleteButton).contains(tintMarker))
    }

    private func makeContentView() -> ContentView {
        ContentView(viewModel: ContentViewModel(
            store: ReminderStore(loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation()))
    }
}

#endif
```

> `ContentView`'s `actionMenuRescheduleSheet` (shared tail) already writes the
> macOS cluster's reschedule path; no change there. iOS Skip/Complete
> (`ContentView.swift:507`, `ContentView+ActionMenu.swift:41`) are untouched.

### Verification
#### Automated
- [x] `xcodebuild -scheme SingleThread -destination 'platform=macOS' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadTests/MacOSActionButtonChromeTests` passes
- [x] `make test` passes (iOS unaffected)
- [x] `make format` clean, then `make lint` clean (watch for `accessibility_label_for_image` — all four controls keep their `.accessibilityLabel` on the control, and `deprecated .menuStyle` — the modern `.menuStyle(.borderlessButton)` spelling is used)

#### Manual
- [ ] None yet — Stage 4 covers the rendered result.

---

## Stage 4: Visual verification & full gate

No code changes. Confirms the visual parity the headless tests can't, and runs
the full CI-identical gate once.

### Verification
#### Automated
- [ ] `make mac-build` succeeds (`CODE_SIGNING_ALLOWED=NO`, macOS build — also proves `SWIFT_TREAT_WARNINGS_AS_ERRORS` accepts the new modifiers)
- [ ] `make mac-test` full macOS unit suite green
- [ ] `./scripts/test.sh` fully green (formats, lints, builds, Periphery, iOS + macOS + watch unit/UI) — run ONCE, as the final gate

#### Manual (launch the macOS app)
- [ ] `make mac-run` launches the macOS build
- [ ] Settings gear (top-right) renders glyph-on-circle with **no translucent square**
- [ ] Refresh (top-left) renders glyph-on-circle with **no translucent square**
- [ ] Mic renders glyph-on-circle, and pressing it shows the red recording plate with **no translucent square**
- [ ] Bottom-bar cluster reads as four matching mono circles (Complete / Skip / Delete / action Menu) in **both light and dark appearance**
- [ ] Hover/press feedback still fire on all cluster controls
- [ ] If the action Menu's plate does not sit flush with the other three circles (the one open risk), adjust the menu label padding in `ContentView+ActionMenu.swift` and re-run Stage 3 tests — do not chase it via new pixel assertions

---

## Final checklist of files touched

| File | Action |
|---|---|
| `SingleThread/SingleThreadButtonModifier.swift` | create |
| `SingleThreadTests/SingleThreadButtonModifierTests.swift` | create |
| `SingleThread/ContentView.swift` | modify (gear/refresh/mic `.singleThreadButton()`) |
| `SingleThreadTests/SingleThreadTests.swift` | modify (refresh signature + 3 new tests) |
| `SingleThread/ContentView+ActionMenu.swift` | modify (4 macOS cluster controls) |
| `SingleThreadTests/MacOSActionButtonChromeTests.swift` | create |