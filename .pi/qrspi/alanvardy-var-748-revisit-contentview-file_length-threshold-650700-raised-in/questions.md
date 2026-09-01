# Research Questions

## Context

Focus on `SingleThread/ContentView.swift` (the app's single-screen main view),
the SwiftLint configuration in `.swiftlint.yml` and `scripts/test.sh`, the view
and modifier organization of the `SingleThread/` app target, and the test
suites (`SingleThreadTests/`, `SingleThreadUITests/`) that exercise the main
screen. Trace how the file is structured, measured, linted, and tested today —
what exists and how it works, with `file:line` references where possible.

## Questions

1. **ContentView.swift structure & size distribution.** What is the full
   top-level structure of `SingleThread/ContentView.swift` today — the
   `ContentView` struct, any extensions on it, preview helpers, and `#Preview`
   blocks (with line ranges)? How are lines distributed across `body`, stored
   properties, computed `some View` sub-views, private helper functions, and
   the conditional-compilation (`#if os(iOS)` / `#if os(macOS)`) blocks? What
   is the file's raw line count, and how does it compare to what SwiftLint's
   `file_length` and `type_body_length` rules actually count (raw lines vs
   comment/whitespace-excluded)? Which sub-views are the largest by line count?

2. **SwiftLint size rules & current thresholds.** In `.swiftlint.yml`, what are
   the exact thresholds for `file_length`, `type_body_length`, and any other
   size-limiting rules (e.g. `line_length`, `cyclomatic_complexity`,
   `function_body_length`)? What is the history of the `file_length` threshold
   (650 → 700 — which commit/PR/spec changed it, and what was the rationale)?
   Which files in the repo currently carry `// swiftlint:disable file_length`
   or `// swiftlint:disable:next type_body_length` directives, and what are the
   measured sizes at those sites? How is the lint gate wired in
   `scripts/test.sh` / the Makefile / CI (strict mode, which paths are linted)?

3. **Compiler type-check budget in ContentView.** Where in ContentView does
   the compiler's expression type-checking get stressed, and how is that
   handled today? Trace the `body` modifier chain and the extracted helpers
   (`setBackgroundPinned`, `settingsSheetContent`, `settingsSheetWritebacks`):
   what do the comments say about why each was extracted, how long are the
   modifier chains, and what is the relationship between the type-check
   workarounds and the file/type body size limits? Are there other spots in the
   codebase with similar "extracted because of type-check budget" comments or
   known type-check-error history?

4. **View / modifier / sub-view organization conventions.** What are the
   established ways views are decomposed in the `SingleThread/` (and watch)
   targets: separate files per view (e.g. `ReminderCardView.swift`,
   `SettingsView.swift` + its sub-view files), shared `ViewModifier`s in their
   own files (e.g. `ControlPlateModifier.swift`, `TextSizeModifier.swift`),
   nested private types (e.g. `PurchaseSheet`, `UpgradePromptButton` in
   `PurchaseSettingsView.swift`, `BackgroundPhotoLayer` in
   `BackgroundImageStore.swift`), and computed `some View` properties? For each
   pattern, give examples with file paths and how they're composed into parent
   views. How do sub-views receive their inputs — bindings, plain values, or
   view models?

5. **State, persistence, and cross-platform wiring in ContentView.** How does
   ContentView's state flow work: which `@AppStorage` keys (and which
   UserDefaults suites — `standard` vs `AppGroup.defaults`), `@State`,
   `@Environment`, and bindings does it hold, and which are platform-gated
   (`#if os(iOS)`)? How does the `SettingsBindings` bag get created on sheet
   presentation and written back via `.onChange`? Where do settings values
   round-trip to the watch via the App Group? What is `ContentViewModel`'s
   role relative to ContentView (what state lives where), and how is
   `BackgroundImageStore.setPinned` invoked?

6. **Test coverage that exercises ContentView.** Which unit tests
   (`SingleThreadTests/`) render `ContentView` or its sub-views — with what
   fixtures/injected stores (e.g. `loadsReminders:`, `InMemoryEventStore`,
   `--seed` JSON) — and what do they assert? Which UI tests
   (`SingleThreadUITests/`) drive the main screen, and what launch-arg seams do
   they use (`--seed`, `--ui-testing`, `--ui-testing-glow`,
   `--ui-testing-notifications`, `--reset-*`)? How is `ReminderCardView`
   tested in isolation (as a precedent for extracting testable sub-views)?
   Which of these tests would be affected by re-homing ContentView's code into
   separate files/types (i.e. which reference ContentView directly)?