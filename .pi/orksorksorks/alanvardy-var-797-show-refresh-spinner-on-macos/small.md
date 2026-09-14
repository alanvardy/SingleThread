# Task

**VAR-797 — Show refresh spinner on macOS.** When the user taps the refresh button in the macOS window of the SingleThread app, the button's arrow icon should be replaced by a moving refresh spinner for at least one second, so the user gets feedback that the tap worked.

The macOS-only refresh button lives in `SingleThread/ContentView.swift:199-213` — an `.overlay(alignment: .topLeading)` inside `#if os(macOS)`:

```swift
Button {
    Task { await viewModel.refreshManual() }
} label: {
    Image(systemName: "arrow.clockwise")
        .font(.title3)
        .controlPlate()
}
.singleThreadButton()
.disabled(viewModel.isRefreshing)
.accessibilityLabel("Refresh")
.accessibilityIdentifier("refreshButton")
.accessibilityAddTraits(.isButton)
```

**What already exists (do NOT re-implement):** `ContentViewModel.refreshManual()` (`SingleThread/ContentViewModel.swift:205-220`) already guards against re-entrant taps, toggles `isRefreshing`, and holds the flag for ≥1 s via `MinimumDisplayDuration.remainingSleep(elapsed:, minimum: 1)` (`SingleThreadCore/Sources/SingleThreadCore/MinimumDisplayDuration.swift`). The state and the one-second hold are done — only the spinner *visual* is missing.

**Change required:** conditionally swap the label for a spinner while refreshing, mirroring the existing in-repo precedent at `SingleThread/BackgroundSettingsView.swift:57-72` — its "Refresh wallpaper" button label is `if backgroundImage.isRefreshing { ProgressView() }` alongside `.disabled(backgroundImage.isRefreshing)` and an accessibility value of "Refreshing" (`:69-71`). Follow that shape: show `ProgressView()` (in the control plate) in place of the `arrow.clockwise` image while `viewModel.isRefreshing` is true, keeping `.disabled(viewModel.isRefreshing)` so the spinner's visibility and re-entrancy stay consistent.

**Testing (required, per repo conventions):** `SingleThreadTests/SingleThreadTests.swift:73-100` — `contentViewBodyContainsRefreshButtonOnMacOS` — pins the button's structural signature (`Button<ModifiedContent<ModifiedContent<Image, …>, SingleThreadButtonModifier>, _EnvironmentKeyTransformModifier<Bool>>, AccessibilityAttachmentModifier`) via `String(describing: view.body)`. This assertion **must be updated in lockstep** with the label change (the `Image` gets wrapped in a conditional, changing the generic signature). `MacOSActionButtonChromeTests.swift` is the precedent for lockstep structural assertions. Unit tests are Swift Testing (`import Testing`, `@Test`); names must not start with `test`/`testing`; identifiers ≥3 chars.

**Verification:** iOS/watchOS/watch-widget and the non-macOS compile paths are untouched (`#if os(macOS)` scopes the button). Phase verification is a build plus a targeted `-only-testing:SingleThreadTests` run on the macOS destination (`make mac-build` / `xcodebuild -destination 'platform=macOS'`) — the full `./scripts/test.sh` gate runs once later via `run-gate`. The watch app is unaffected.

## Why SMALL

All of A–F hold: single module, 1 code file + 1 test file, follows the existing `BackgroundSettingsView` ProgressView-in-button-label pattern; zero unknowns (state + 1 s minimum-display hold already implemented and tested); no schema, no new subsystem, no shared/convention code; no design decision (spec explicit); tests are one lockstep structural assertion update plus optionally a view-level check.

## Key files

- `SingleThread/ContentView.swift:199-213` — the refresh button (macOS-only overlay); swap/append the spinner in the label.
- `SingleThread/BackgroundSettingsView.swift:57-72` — precedent: `if isRefreshing { ProgressView() }` in a button label + `.disabled`.
- `SingleThread/ContentViewModel.swift:205-220` — `refreshManual()`; already holds `isRefreshing` ≥1 s (do not re-implement).
- `SingleThreadCore/Sources/SingleThreadCore/MinimumDisplayDuration.swift` — helper backing the 1 s hold.
- `SingleThreadTests/SingleThreadTests.swift:73-100` — `contentViewBodyContainsRefreshButtonOnMacOS` signature assertion to update in lockstep.
- `SingleThreadTests/MacOSActionButtonChromeTests.swift` — precedent for `#if os(macOS)` structural tests.