# Task

On the iPhone Duo's **outer screen in portrait only**, halve the horizontal padding so the checklist/reminder card gets wider. Every other screen and orientation must keep its current padding.

The ticket points at `../CheckStitch` as the reference implementation — the same Duo-outer-screen layout adaptation was already done there. Reuse that pattern: a pure, unit-testable layout policy (context → width/inset) plus a device/size-class detector in the app target. In this repo the relevant surfaces are the card width cap (`SingleThread/CardWidth.swift`, used by `EmptyStateCard` and the reminder card in `ContentView.swift`) and the horizontal padding currently applied around the card (`ContentView.swift:498` uses `.padding(.horizontal, 40)`; the iOS header uses `.padding(.horizontal, 40)` in `ContentView+iOS.swift`). The default (non-Duo) path must remain `min(340, viewportWidth * 0.6)`.

Note: this repo currently has no Duo detection (only "Fixture iPhone Duo" device fixtures); the CheckStitch implementation's `DuoDisplay` / `DuoOuterPortrait` approach (uname machine identifier + compact-width/regular-height size classes) is the pattern to port.

# Why MEDIUM

MULTI_MODULE + BROAD_TEST_SURFACE: the change spans a pure layout helper, its call sites in the iOS/macOS shared view, and the iOS header, with a device detector and unit tests; the approach is already established in `../CheckStitch`, so no design decision or new subsystem is needed.

# Key files

- `SingleThread/CardWidth.swift` — current pure width cap (`min(340, 0.6W)`), to extend with a Duo context.
- `SingleThread/EmptyStateCard.swift` — delegates to `CardWidth.maxContentWidth`.
- `SingleThread/ContentView.swift` — reminder list/card (`~434–498`, `.padding(.horizontal, 40)`), the primary width/padding call site.
- `SingleThread/ContentView+iOS.swift` — iOS header row (`.padding(.horizontal, 40)` around `~168–177`).
- `SingleThreadTests/CardWidthTests.swift` — existing pure-math tests to extend.
- `SingleThreadTests/AppDelegateTests.swift` — precedent for iOS-only unit tests in the app target.
- Reference: `../CheckStitch/CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift`, `DuoDisplay.swift`, `CheckStitch/DuoOuterPortrait.swift`, `CheckStitchTests/ChecklistLayoutTests.swift`.
