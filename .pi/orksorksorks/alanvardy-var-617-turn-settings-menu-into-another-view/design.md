# Design Discussion

Replacing the settings `Menu` (gear, top-trailing overlay) with a separate
settings screen. Presented as a **modal sheet** with a "Done" button, keeping
the same persisted preferences and their effects.

## Current State

- `ContentView` is a single-root `ZStack` with **no navigation container of any
  kind** in the repo (research found zero `NavigationStack`/`NavigationLink`/
  `NavigationView` matches).
- The app scene is one `WindowGroup` rendering exactly one view:
  `SingleThreadApp.swift:43-45` (`ContentView(store: store)`).
- The gear settings control is a SwiftUI `Menu` hosted via
  `.overlay(alignment: .topTrailing)` at `ContentView.swift:47-51`.
- The `Menu` (`ContentView.swift:273-303`) holds, in order:
  1. `Picker("Appearance")` over `AppearanceMode.allCases` (275-280).
  2. `Picker("Text Size")` over `TextSize.allCases` (281-286).
  3. iOS-only `Toggle("Landscape")` with `.onChange` → `AppDelegate.applyLock`
     (287-294, `#if os(iOS)`).
  4. `Toggle("Microphone")` (295).
- The `Menu` label is `Image(systemName: "gearshape")` with
  `.accessibilityLabel("Settings")` (296-303).
- `ContentView` **owns all four `@AppStorage` vars** and applies their effects:
  - `appearanceMode`, `textSize`, `allowsLandscape` (iOS-only),
    `showMicrophoneButton` at `ContentView.swift:91-103`.
  - `.preferredColorScheme(appearanceMode.colorScheme)` at `ContentView.swift:55`.
  - `.modifier(TextSizeModifier(textSize: textSize))` at `ContentView.swift:56`
    (modifier defined at `ContentView.swift:427-443`).
- `AppDelegate` reads the raw `"allowsLandscape"` UserDefaults key independently
  (key-literal duplicated: `ContentView.swift:98` and `AppDelegate.swift:34-36`),
  supplying a launch-time default to avoid a wrong-orientation flash
  (`AppDelegate.swift:7-10,32-38`).
- Option enums `AppearanceMode` / `TextSize` follow the same
  `String, CaseIterable` pattern with `colorScheme`/`dynamicTypeSize`,
  `systemImage`, and `title` computed properties
  (`AppearanceMode.swift:16-41`, `TextSize.swift:18-48`).
- View-level tests assert on `String(describing: view.body)` —
  `MicrophoneToggleTests.swift:34-84` asserts the body contains `"Microphone"`
  and does *not* contain `"mic.fill"`; the UI accessibility audit
  (`SingleThreadUITests.swift:15-42`) only exercises the main screen, never a
  presented sheet.

## Desired End State

- The gear becomes a plain `Button` (not a `Menu`) that opens a modal sheet.
- `SettingsView` (new standalone file) presents the four preferences as rows in
  a `Form`, bound to the same `@AppStorage` state.
- The user dismisses via a "Done" toolbar button or swipe-down to return to the
  main list.
- Existing persisted state is unchanged — no keys renamed, no defaults altered —
  so users keep their current appearance/text-size/landscape/mic preferences.

### Verification

- `./scripts/test.sh` passes (format, lint, build, Periphery, unit, UI + audit).
- Unit tests: (a) `ContentView.body` still exposes the gear (so the entry point
  is present); (b) `SettingsView.body` contains the `"Microphone"` toggle and
  the appearance / text-size / landscape rows.
- `AppDelegateTests` and `AppearanceModeTests` / `TextSizeTests` remain green
  unchanged (no behavior change to the orientation lock or enum mappings).
- Manual: open the gear → four settings appear in a sheet; toggling appearance
  and text size reflects live; landscape toggle still applies the orientation
  lock; mic toggle still gates the mic button on the main list.

## Patterns to Follow

**Follow:**

- **Root-level `@AppStorage` + `@Binding` into child views** — `ContentView`
  already owns all preference state and applies all effects; `SettingsView`
  should stay a pure presentational view receiving bindings.
- **One type/concept per file** — add `SettingsView.swift` as a standalone
  `View` file (precedent: `WatchReminderView.swift`), not another private
  computed property in `ContentView.swift`.
- **Platform gating with `#if os(iOS)`** in both the property/store and the UI
  (`ContentView.swift:97-100,287-294`) — mirror this for the landscape binding
  and its toggle in `SettingsView`.
- **`String, CaseIterable` enums as pickers** — keep using `ForEach(…, id: \.self)`
  with `Label(mode.title, systemImage: mode.systemImage).tag(mode)` (as in
  `ContentView.swift:275-286`).
- **Accessibility traits on buttons** — add `.accessibilityLabel("Settings")`
  and `.accessibilityAddTraits(.isButton)` (SwiftLint
  `accessibility_trait_for_button` requires the trait).
- **`// MARK:` organization** + SwiftFormat `organizeDeclarations`/`blankLinesAroundMark`.

**Do NOT follow:**

- **Key-string literals scattered across files** — the `"allowsLandscape"`
  duplication (`ContentView.swift:98` / `AppDelegate.swift:34-36`). We will not
  introduce a new shared-constant refactor here (see "What We're NOT Doing"),
  but we must not add *new* duplicate literals.
- **`String(describing:)` as a spec** — keep using it only where it already works
  (presence of SF Symbols / button titles), and do not assert layout/placement
  with it (it cannot test overlay alignment).

## Design Decisions

1. **Presentation is a modal `.sheet` (not `NavigationStack`)** — chosen over a
   pushed navigation screen. Trade-off: a sheet has no "back button in the
   top-left" as the task literally described; the return affordance is a "Done"
   toolbar button plus swipe-down. This is a deliberate, reviewable divergence
   (recorded here and in Open Risks). The gear stays in
   `.overlay(alignment: .topTrailing)` — no `NavigationStack` or `.navigationTitle`
   is introduced.
2. **State ownership stays in `ContentView`** — all four `@AppStorage` vars
   remain in `ContentView.swift:91-103`; `SettingsView` receives `@Binding`s.
   `.preferredColorScheme` and `TextSizeModifier` stay on the root so the whole
   tree (main list) keeps behaving exactly as today.
3. **`SettingsView` re-applies appearance + text-size effects to itself** — the
   sheet content applies `.preferredColorScheme(appearanceMode.colorScheme)` and
   `.modifier(TextSizeModifier(textSize:))` so (a) changing text size inside the
   sheet gives live feedback, and (b) we don't rely on sheet environment
   inheritance, which is inconsistent across platforms.
4. **Settings container is a `Form`** — a `Form` with rows (appearance picker,
   text-size picker, landscape toggle, microphone toggle) gives the idiomatic
   settings look with standard, accessible row styling on both iOS and macOS.
   Pickers keep their `ForEach(…, id: \.self)` label/tag construction.
5. **Landscape toggle + orientation side-effect stay co-located** — the
   `Toggle("Landscape")` and its `.onChange { AppDelegate.applyLock }` move
   together into `SettingsView`, wrapped `#if os(iOS)` exactly as today
   (`ContentView.swift:287-294`); `SettingsView` takes the `allowsLandscape`
   binding under `#if os(iOS)`, and the `.sheet` call site passes it under the
   same guard. macOS builds the `Form` with the three cross-platform rows only.
6. **Gear `Menu` becomes a plain `Button`** — `Button { isShowingSettings = true }`
   labeled `Image(systemName: "gearshape")` keeping the existing frame,
   `.contentShape`, `.foregroundStyle(.secondary)`, and `.accessibilityLabel`,
   plus `.accessibilityAddTraits(.isButton)`. A `@State private var
   isShowingSettings = false` drives `.sheet(isPresented:)`.
7. **Dismissal via `@Environment(\.dismiss)`** — a "Done" button placed with
   `ToolbarItem(placement: .confirmationAction)` (renders top-trailing on iOS,
   appropriate placement on macOS); swipe-down remains available on iOS. No
   navigation title.
8. **Tests split (no new infra)** — keep the `String(describing:)` idiom:
   - `ContentView`-level: assert `String(describing: view.body).contains("gearshape")`
     (mirrors the existing `"mic.fill"` technique in
     `MicrophoneToggleTests.swift:44-60`) to prove the settings entry point survived.
   - `SettingsView`-level: construct with `Binding.constant(...)` and assert the
     body contains `"Microphone"`, `"Appearance"`, `"Text Size"`, and (iOS-only)
     `"Landscape"`. Cross-platform tests gate the `allowsLandscape` argument with
     `#if os(iOS)` since unit tests also run on macOS.

## What We're NOT Doing

- **No `NavigationStack` / `NavigationLink` / navigation title** anywhere.
- **No shared `@AppStorage` key-constant refactor** — the pre-existing
  `"allowsLandscape"` literal duplication is acknowledged but left alone; we add
  no new duplicate literals either.
- **No UI test that opens the sheet** — the accessibility audit continues to
  exercise only the main screen; navigation into settings is covered by unit
  tests on `SettingsView.body`.
- **No watch-side parity** — `WatchReminderView` has none of these preferences
  today and stays untouched.
- **No changes to enum shapes, key names, or defaults** — persisted
  `UserDefaults` values must remain backward compatible.
- **No reordering/re-theming of settings beyond moving them into a sheet.**

## Open Risks

- **Task-wording divergence**: "back button in the top-left" vs. a modal sheet's
  "Done" + swipe-down. If a literal top-left back control is required, this plan
  pivots to `NavigationStack` (Decision 1) — the rest of the design is
  orthogonal to that change.
- **Sheet environment inheritance**: `.preferredColorScheme` / `.dynamicTypeSize`
  may not propagate into a presented sheet automatically on all platforms;
  mitigated by Decision 3 (re-apply inside `SettingsView`). Confirm on macOS.
- **`String(describing:)` brittleness**: assertions depend on SF Symbol names
  and control titles appearing in the body description; this matches the
  existing idiom but offers no structural guarantees.
- **macOS `Form` rendering**: `Form` looks different on macOS and omits the
  iOS-only landscape row; acceptable per Decision 5, but worth a manual sanity
  check via `make mac-build`.
- **`Binding.constant` in `SettingsView` tests** may need `#if os(iOS)` guard
  around the `allowsLandscape` argument to compile on the macOS test job.