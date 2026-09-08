# Research Questions

## Context

This is a SwiftUI app whose main app target compiles for iPhone, iPad, and macOS from one set of view files, with a separate watchOS target and widget extension. Shared views diverge per platform through `#if os(...)` branches and cross-platform helpers, and button appearance is a mix of explicit styles, custom plate modifiers, and the platform default style. The research maps how buttons are styled, how the custom appearance modifiers compose with SwiftUI's platform-dependent button chrome, how per-platform view code is structured, how colors adapt to light and dark appearance, and how appearance is verified by tests.

## Questions

1. **Button styling inventory**: Across the iOS+macOS app target, the watch target, and the widget, which buttons exist and how is each styled? Enumerate every `Button` and its explicit modifiers (`.buttonStyle`, `.tint`, `.background`, `.foregroundStyle`, `.shadow`, `.labelStyle`), noting which buttons rely on the platform default style. How does the default SwiftUI `Button` style render on macOS versus iOS for identical view code?

2. **Appearance modifier composition**: How do the custom appearance modifiers (`controlPlate()`, `cardPlate()`, and related plate helpers) work? What exactly do they draw — shape, fill color, glyph color, frame, shadow — and how do they compose with the `Button`'s own platform chrome? Does the modifier replace the button style or sit underneath/around it?

3. **Cross-platform view conventions**: What conventions exist for writing one SwiftUI view that renders on both macOS and iOS? Map the `#if os(...)` branches, the cross-platform helpers (`Color+CrossPlatform`, `SettingsSubscreenLayout`, `AppearanceMode`, etc.), and any existing pairs of iOS/macOS implementations of the same control (e.g. the bottom-bar action buttons in `ContentView` and `ContentView+ActionMenu`). Which views deliberately differ per platform and how is that divergence structured?

4. **Light/dark appearance adaptation**: How do button colors and backgrounds adapt to light and dark appearance across platforms? Trace the scheme-adaptive fill colors (plate fills, glyph colors), the `Color.systemBackground` cross-platform mapping, and how `AppearanceMode` handles `UIUserInterfaceStyle` versus `NSAppearance`. Where in the existing view tree is white-on-black / black-on-white contrast already implemented, and how is it composed?

5. **Testing button appearance**: How do existing tests assert on button appearance and platform-specific rendering? Survey unit tests that introspect reflected view styles or colors (e.g. `SwipePromptTests`, `BackgroundCardTests`), and UI tests with per-platform branches or accessibility-audit splits. What test infrastructure exists to verify that a control renders the same visual treatment across platforms?