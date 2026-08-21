# Design Discussion

## Current State

`SettingsView` (`SingleThread/SettingsView.swift`) is a modal `NavigationStack { Form { … } }` (`:110-111`) presented from the gear button via `.sheet(isPresented: $isShowingSettings)` (`ContentView.swift:104`). It owns no state; every row binds back to `ContentView`'s `@AppStorage` values (`ContentView.swift:184-209`). Nine rows exist:

- **3 Picker rows** — Appearance (`:112-117`), Text Size (`:118-123`), Sort By (`:124-129`). Titles/icons source from SwiftUI-aware enums (`AppearanceMode.swift:46-63`, `TextSize.swift:29-45`, `SortOption+Presentation.swift:10-23`). No per-case descriptions today.
- **5 Toggle rows** — Allow Landscape (`:130-137`, iOS-only), Show Microphone (`:138-140`), Enable action buttons (`:141-145`, iOS-only), Show Undated (`:146-148`), Show Date (`:149-155`). All use literal `Label("…", systemImage:)` strings + `.onChange` consumers.
- **1 NavigationLink row** — Excluded Projects (`:157-166`) → `ExcludedProjectsView` submenu (`:12-51`), which itself has a footer literal `Text("Excluded projects are hidden from the reminder list.")` (`:31`).

Platform split is pervasive: iOS-only rows (`allowsLandscape`, `enableActionButtons`) gated by `#if os(iOS)`, two init overloads (iOS 10-arg `:63-78` / `#else` 8-arg `:86-93`), mirrored in `ContentView.swift:105-131`. watchOS never compiles `ContentView`/`SettingsView` (routes around settings entirely — `SingleThreadWatch` has no settings sheet).

All settings copy is inline, plain-English Swift literals. No localization key framework exists for settings (grep found none in the app target). SF Symbol identifiers are dotted-lowercase (`"rectangle.landscape.rotate"`, `"calendar.badge.minus"`).

## Desired End State

Every preference row in `SettingsView` gains an info affordance the user can tap to reveal a short, accurate description of what the setting does. Descriptions reflect only the behavior each row **actually implements** (traced in Q4 research — none are hollow):

| Row | Behavior to describe |
|---|---|
| Appearance | Choose light/dark/system styling (`AppDelegate.applyAppearance` `AppDelegate.swift:15-22`, macOS `MacAppDelegate` `:72-75`) |
| Text Size | Scale reminder text (`TextSizeModifier` `ContentView.swift:547-553`) |
| Sort By | Reorder visible reminders (`ReminderStore.setSortOption` `:230-234`, `ReminderSort.swift:24-54`) |
| Allow Landscape (iOS) | Allow rotate into landscape (`AppDelegate.applyLock` `AppDelegate.swift:31-42`) |
| Show Microphone | Show the dictation mic button (`ContentView.swift:410`) |
| Enable action buttons (iOS) | Replace mic with Complete/Skip cluster (`ContentView.swift:56-58`, `:410-414`) |
| Show Undated | Surface undated reminders (`ReminderStore.swift:100-104`) |
| Show Date | Show due dates on cards + `WidgetCenter.reloadAllTimelines` (`ReminderCardView.swift:33-34`, `SettingsView.swift:152-156`) |
| Excluded Projects | Hide selected projects from list (`ReminderStore.setExcludedProjectTitles` `:311-317`) |

**Verification:** (1) unit test covers each row description via `String(describing: view.body)`; (2) SwiftLint `accessibility_label_for_image` + `accessibility_trait_for_button` force label + `.isButton` on new icon affordances; (3) UI test opens Settings, taps the info affordance, asserts description text.

## Patterns to Follow

- **Row patterns** — mirror the existing structure: picker/toggle rows already use consistent `Label` + `systemImage` and `.onChange`; attach the help affordance at the row level, matching this grain.
- **`View.help(_ text: Text)`** — the SDK's built-in info affordance. iOS 14+/macOS 11+ (`@available` in `arm64e-apple-ios.swiftinterface:23398-23407`; `help(_ textKey:)` `:23398`, `@_disfavoredOverload help<S>(_ text: S)` `:23407`). Native ″ⓘ″, tap-to-reveal, system-managed accessibility. This is the chosen mechanism (Q1A).
- **`Section(content:header:footer:)` / `NavigationLink` submenu** — the existing submenu pattern (`SettingsView.swift:12-32`) is the model for any grouping; the `ExcludedProjectsView` footer already reads like description copy (`:31`).
- **Accessibility attach style** — gear button `.accessibilityLabel("Settings") + .accessibilityAddTraits(.isButton)` (`ContentView.swift:80-81`) is the codebase's interactive-affordance pattern; SwiftLint `accessibility_trait_for_button` + `accessibility_label_for_image` are enabled (`swiftlint.yml:45-46`) so all new info affordances must be labeled + button-traited.
- **Literal copy** — inline string literals for descriptions, consistent with the toggle rows' literal `Label("…")` (`SettingsView.swift:139,143,147,150`) and toolbar `Button("Done")` (`:169`). No localization layer.
- **Unit test pinning** — extend `SettingsViewTests.swift` (currently `:8-49`) so every new description is assertable; its comment (`:37-39`) confirms `Form` body is reflective.
- **UI test driving** — `--ui-testing` + `XCUIApplication().buttons["Settings"].tap()` + `app.staticTexts["…"].waitForExistence` is the existing iOS settings-drive pattern (`SingleThreadUITestsFlows.swift:126-139`); extend it to tap the info affordance.

**Patterns NOT to follow:**
- **Does NOT follow** `popover(isPresented:)` / `popover(item:)` (iOS–now, `swiftinterface:11596,11637`) — needs ~10 per-row `@Binding Bool` fields + custom trailing control + manual dismiss; rejected in favor of `View.help` (Q1B).
- **Do NOT add a localization layer.**
- **Do NOT copy macOS-only `HelpLink` struct disable (`swiftinterface: `17345)` — macOS 14+ only, not cross-platform; `View.help` covers both.

## Design Decisions

1. **Mechanism: `View.help(…)`** — the built-in info affordance rather than custom popovers. Reason: task's "info control the user can tap to reveal a short pop-up" is exactly what `View.help` provides; avoids ~10 new bindings, per-row dismiss handling, and reimplements system accessibility. Applied as a row-level `.*.help(Text("…"))`.
2. **Description copy: inline text literals** in concrete string literals. Reason: matches the written `Label("…")` convention (`SettingsView.swift:139,150`); no localization layer exists; avoids a parallel keyed structure (which would be awkward for the non-enum toggles).
3. **Scope: row-level only.** Reason: the task enumerates preference rows (Appearance/Text Size/Sort By/toggles/Excluded Projects), and per-case picker descriptions (System/Light/Dark, etc.) are explicitly out of scope (Q3B).
4. **Cross-platform: `View.help` is iOS+macOS; iOS-only rows gate with existing #if `os(iOS)`.** The `allowsLandscape`/`enableActionButtons` rows keep their `#if os(iOS)` guards so their descriptions only appear where the toggles exist.
5. **Testing: unit test (row descriptions) + UI test (tap-through).** Run the existing unit assert pattern, and add a `SingleThreadUITests` flow test asserting the info affordance reveals text. This satisfies `AGENTS.md`'s UI-test-for-flows requirement (`:**69-79` in AGENTS.md).

## What We're NOT Doing

- No custom `popover(item:)/isPresented:` overlays. No new `.sheet`/`.alert`/`.confirmationDialog` for descriptions — `View.help` is the sole affordance.
- No per-case description inside the three `Picker` menus (Appearance/Text Size/Sort By sub-values).
- No localization/StringCatalog layer — descriptions stay plain-English literals.
- **No Mac-only `.help` on the watch target** — watchOS has no settings sheet (`View.help` also has macOS availability, but watchOS isn't expected to render it anyway).
- No copy editing pass to `ExcludedProjectsView`'s footer copy beyond what's already there.
- No persistence/state changes — `View.help` needs no new stored bindings.

## Open Risks

- **`String(describing: view.body)` may not reflect `.help(…)` text.** `View.help` renders behind the default ″ control; the description may NOT appear in `bodyDescription` the way row labels do (`SettingsViewTests.swift:37-39`). Design decision: unit test will assert `description` only if it surfaces — otherwise the UI test is the backstop. Flag during implementation if the unit `contains` fails for `.help`.
- **Tapping an info affordance in XCTest** may need new accessibility trait/query by label. SwiftLint + the audit aim to keep this reachable; the UI test must locate the info control (likely via `.accessibilityLabel`).
- **SwiftUI SDK polymorphism**: `swiftinterface: R1` line numbers (11596/11637/23398) apply to installed Xcode 26 and may shift.
- **Copy accuracy drift** — descriptions must match real behavior (Q4 table). Any preference behavior change later must update its description.
- **TextSizeModifier / Appearance on macOS** already apply server-side — descriptions must not claim behavior that is platform-limited.