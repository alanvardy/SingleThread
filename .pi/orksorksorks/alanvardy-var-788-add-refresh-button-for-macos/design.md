# Design Discussion

## Current State

- **No macOS refresh surface**: The only manual reminder-refresh controls in the app are iOS `.refreshable` (inert on macOS — no pull gesture, `ContentView.swift:403-405,416-418,493-496`) and the watch refresh button (`WatchReminderView.swift:187-193`). macOS users must kill and relaunch the app to pick up changes from other devices (watch, iPhone) or background EventKit syncs.
- **macOS top-left corner is empty**: Overlays are settings gear at top-trailing (`ContentView.swift:184-199`) and iOS-only undo/notification seams at top-leading (`ContentView.swift:200-218,224-231`). The top-left (``.overlay(alignment: .topLeading)`) has no control — it's the natural mirror position for a new floating button.
- **`ReminderStore.reload(clearSkipped:)` has no in-flight guard** (`ReminderStore.swift:412-416`). The method is fully re-entrant; overlapping calls interleave freely. The watch solves this with `WatchReminderViewModel.isRefreshing` + `guard !isRefreshing` + a 1 s minimum-display hold using `MinimumDisplayDuration` (`WatchReminderViewModel.swift:46,108-120`). iOS/macOS have no equivalent — the system `.refreshable` spinner is opaque and unguarded.
- **`clearSkipped` semantics are split across platforms**: The watch passes `store.allSkipped` dynamically (`WatchReminderView.swift:189,209`), un-hiding skipped reminders only when the visible list is entirely skipped. iOS `.refreshable` splits the logic: all-skipped empty-state passes `true`, populated-list passes `false` (`ContentView.swift:404,416,493`). The internal `ReminderStore.reconcileSkipState` (`ReminderStore.swift:648-660`) handles both paths correctly.
- **macOS testing is unit-only**: `make mac-test` (`Makefile:26-27`) and `scripts/test.sh:283-295` both run `-only-testing:SingleThreadTests` (Swift Testing unit tests). The `SingleThreadUITests` bundle is macOS-capable (`project.pbxproj:768,818,844,873,901,925` — all six build configs have `MACOSX_DEPLOYMENT_TARGET = 26.5`) and existing audit tests compile a macOS `#else` branch (`SingleThreadUITests.swift:62-65`), but no invocation exists in Makefile, `scripts/test.sh`, or CI (`ci.yml:270-320`). New macOS UI features have no test path.
- **`ContentView.swift` is near the file-length threshold**: `type_body_length` warning at 650 lines, error at 800 (`.swiftlint.yml:29-35`). Extensions (`ContentView+iOS.swift`, `ContentView+Settings.swift`) already split iOS-specific code; macOS code lives directly in `ContentView.swift` (e.g. `actionButtons` :328-371, settings min frame :593-595).

## Desired End State

A refresh button in the macOS top-left corner that matches the settings gear visually, leverages the watch refresh pattern for in-flight state, and ships with both unit and macOS UI test coverage.

### Button specification

| Property | Value |
|----------|-------|
| **Glyph** | `Image(systemName: "arrow.clockwise")` |
| **Style** | `.controlPlate()` — 56×56 circle, adaptive fill/shadow (`ControlPlateModifier.swift:14-31`) |
| **Position** | `.overlay(alignment: .topLeading)` + `.padding(.top, 8).padding(.leading, 12)` — mirror of gear's `.topTrailing` + `.trailing, 12` |
| **Platform gate** | `#if os(macOS)` — absent on iOS (pull-to-refresh suffices) |
| **Label** | `"Refresh"` — reused from Core catalog (`SingleThreadCore/…/Localizable.xcstrings`), same key the watch uses |
| **Accessibility** | `.accessibilityLabel("Refresh")` + `.accessibilityIdentifier("refreshButton")` + `.accessibilityAddTraits(.isButton)` |
| **Disabled state** | `.disabled(viewModel.isRefreshing)` — prevents duplicate taps |

### Tap behavior

1. User taps button → `Task { await viewModel.refreshManual() }` (fires and forgets, matching `.refreshable` + watch pattern).
2. `ContentViewModel.refreshManual()`:
   a. `guard !isRefreshing else { return }` — re-entrancy gate.
   b. `isRefreshing = true`; capture `startedAt = Date()`.
   c. `await store.reload(clearSkipped: store.allSkipped)` — dynamic un-hide only when every visible reminder is skipped.
   d. Sleep `remainingSleep(elapsed: Date().timeIntervalSince(startedAt), minimum: 1)` — minimum 1 s display so the spinner doesn't flash (`MinimumDisplayDuration.swift:10-13`); sleep is `try?`-swallowed so the flag always resets.
   e. `isRefreshing = false` (in `defer` block — even on cancellation).
3. `ReminderStore.reload(clearSkipped:)` runs unchanged (no store-level guard added).

### Refresh state surfacing

- **Button disabled** while `isRefreshing` (`.disabled(viewModel.isRefreshing)`).
- **Optional inline spinner**: A `ProgressView()` scale-matched to the button size, conditionally overlaid when `isRefreshing`. This is the pattern from `BackgroundSettingsView.swift:62-70` (wallpaper refresh button — the only other iOS/macOS manual-refresh-with-in-flight precedent). The implementation phase decides the exact spinner placement (inside the button vs. adjacent overlay).
- **No full-screen spinner** — the list remains visible and interactive (other controls — gear, action buttons — stay enabled).

### Verification

| What | How |
|------|-----|
| Button appears on macOS, absent on iOS | Unit test: `String(describing: contentView.body)` contains `"refreshButton"` on macOS; iOS body does not regress |
| Tap triggers reload | Unit test: `ContentViewModel.isRefreshing` toggles true→false after reload |
| `clearSkipped` passes correct value | Unit test: `allSkipped = true` → reload called with `clearSkipped: true`; `false` → `false` |
| Re-entrancy gate | Unit test: rapid double-tap — second call is no-op, `reload()` called exactly once |
| Minimum display hold | Unit test: with no-op settle inject, flag stays `true` ≥ 1 s |
| Accessibility | MacO S UI test: `app.buttons["refreshButton"].exists` + `performAccessibilityAudit` passes CI categories |
| Does not regress iOS | Existing iOS UI tests (flows + audits) still pass |
| CI gate | `./scripts/test.sh` passes including new macOS UI step |

## Patterns to Follow

| Pattern | Source | Notes |
|---------|--------|-------|
| `controlPlate()` circle overlay | `ContentView.swift:185-198` (gear), `ControlPlateModifier.swift:14-31` | 56×56 circle, adaptive fill/glyph (dark = black/white, light = `Color(white: 0.92)`/`Color(white: 0.15)`), `shadow(radius: 4)`. Position via `.overlay(alignment:)` + padding — gear is `.topTrailing` + `.trailing, 12`; refresh mirrors `.topLeading` + `.leading, 12` |
| Three-modifier a11y stack | `ContentView.swift:340-342,353-355,365-367` (macOS actionButtons), `:193-195` (gear) | `.accessibilityLabel` + `.accessibilityIdentifier` + `.accessibilityAddTraits(.isButton)` — applied to 14 icon-only/custom controls across the app |
| VM-owned `isRefreshing` + guard | `WatchReminderViewModel.swift:46,108-120` | `guard !isRefreshing`, capture start time, set/reset flag, minimum-display sleep in `defer`. The VM owns this — `ReminderStore` stays re-entrant |
| `MinimumDisplayDuration` math | `WatchReminderViewModel.swift:113-115`, `MinimumDisplayDuration.swift:6-13` | `remainingSleep(elapsed:minimum:) = max(0, minimum - elapsed)`. Sleep is `try? await Task.sleep(…)` so `defer` always resets the flag even on cancellation |
| `clearSkipped: store.allSkipped` | `WatchReminderView.swift:189,209` | Dynamic argument — only un-hides when every visible reminder is skipped. The watch is the authoritative precedent for user-triggered refresh |
| Manual-refresh in-flight surfacing | `BackgroundImageStore.swift:76,122-129` (store flag), `BackgroundSettingsView.swift:62-70` (view surfacing) | The only other iOS/macOS manual-refresh-with-in-flight-state: `isRefreshing` guard, inline `ProgressView()`, `.disabled(isRefreshing)`, ``.accessibilityValue("Refreshing")` |
| View-structure unit test | `SingleThreadTests.swift:21-31` | `String(describing: view.body)` containment of expected strings — the standard mechanism; limitation: `_ConditionalContent` branches indistinguishable (`ActionButtonTests.swift:12-13`) |
| `--seed` for deterministic UI tests | `UITestingSeed.swift:48-59`, `AppViewModel.swift:329-372`, `SingleThreadUITestCase.swift:20-23` | Seed a known reminder list via `InMemoryEventStore`; `--ui-testing` for persistence-across-relaunch. Use `launchSeeded` for write-flow tests |
| MacO S UI test compilation precedent | `SingleThreadUITests.swift:62-65` | Existing `#if os(macOS)` branch in audit tests — the UITests bundle already compiles and runs on macOS under `platform=macOS` |
| MacO S test destination | `Makefile:8,26-27`, `scripts/test.sh:12,283-295` | Unpinned `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` |

**Do NOT follow**: The bare `Button("Refresh")` text-label pattern from the watch (`WatchReminderView.swift:188`) — macOS floating overlay controls use SF Symbol circles, matching the settings gear. Also, do NOT add a re-entrancy guard inside `ReminderStore.reload()` — the store stays re-entrant; the guard lives at the VM layer (watch precedent). Do NOT use `.toolbar` / `ToolbarItem` / `.commands` — the app has no toolbar infrastructure (`research.md` Q1).

## Design Decisions

1. **In-flight flag in `ContentViewModel` (Option A)**: Mirror `WatchReminderViewModel.isRefreshing` (`WatchReminderViewModel.swift:46,108-120`). `ContentViewModel` already owns the `reload(clearSkipped:)` passthrough (`ContentViewModel.swift:156-158`) — adding the guard, minimum-display hold, and `refreshManual()` entry point there keeps `ReminderStore` re-entrant and avoids coupling the store to UI concerns. The `BackgroundImageStore.isRefreshing` precedent (`BackgroundImageStore.swift:76`) confirms the pattern: manual-refresh-on-iOS/macOS controls use a dedicated in-flight flag, and that flag is owned by the layer closest to the UI (store for background image, VM for reminders — the VM is the right layer here since `ReminderStore` is shared with the watch which has its own flag).

2. **SF Symbol `"arrow.clockwise"` in `controlPlate()` (Option A)**: The settings gear (`ContentView.swift:185-198`) is the sole floating overlay on macOS — positioning a matching `controlPlate()` circle at top-leading creates visual symmetry (refresh-left, settings-right). `"arrow.clockwise"` is the standard reload glyph across Apple platforms. The `Label("Refresh", systemImage:)` approach would depart from both the gear and the watch, and a text-only button would look out of place in the overlay layer. Explicit `.accessibilityLabel("Refresh")` covers the icon-only gap.

3. **Dynamic `clearSkipped: store.allSkipped` (Option B)**: Match the watch exactly (`WatchReminderView.swift:189,209`). The all-skipped state is the one case where "Refresh" should also mean "un-hide everything" — if the user's list is all-skipped, a refresh that shows the same empty state is confusing. For normal lists with visible reminders, `clearSkipped: false` preserves the user's intentional skip choices (they can un-hide deliberately via the saved-changes flow in settings). The VM `refreshManual()` reads `store.allSkipped` at call time — it's a snapshot, not reactive.

4. **Full macOS UI test infrastructure (Option B)**: The task requires UI test coverage for new user-facing flows. A view-structure unit test verifies the button exists in the view hierarchy but cannot verify tap behavior, accessibility audit compliance, or real `ReminderStore` reload under `InMemoryEventStore`. Adding a macOS UI test requires:
   - A new test class (e.g. `SingleThreadUITestsMacOS.swift`) or `#if os(macOS)` test methods in an existing class, using `--seed` for deterministic reminders.
   - A `make mac-ui-test` Makefile target (`platform=macOS`, `CODE_SIGNING_ALLOWED=NO test -only-testing:SingleThreadUITests/SingleThreadUITestsMacOS`).
   - A `scripts/test.sh` step (placed before or after the existing unit-only macOS step).
   - A C I matrix entry in `ci.yml` (after `mac-tests`, same `macos-26` runner). The `SingleThreadUITests` bundle is already macOS-capable — the gap is scheduling, not capability. This also establishes the pattern for future macOS UI features.

## What We're NOT Doing

- **No `reload()` re-entrancy guard in `ReminderStore`**: The store stays re-entrant — overlapping reloads interleave as they do today. The guard lives in `ContentViewModel`, matching the watch pattern (`WatchReminderViewModel.swift:109`).
- **No refresh button on iOS**: iOS already has pull-to-refresh `.refreshable` — this is macOS-only, gated by `#if os(macOS)`.
- **No toolbar, menu bar, or `.commands` refresh**: This is an overlay button like the gear, not a `ToolbarItem` or `MenuBarExtra`. The app has no toolbar/menu infrastructure (`research.md` Q1 confirmed none exists — no `defaultSize`/`windowResizability`/`.commands`/`MenuBarExtra`/toolbars anywhere in `SingleThread/`).
- **No progress indicator in the list body**: The inline `ProgressView()` during refresh is scoped to the button area; it does not replace the main list with a full-screen spinner.
- **No watch changes**: The watch already has its refresh button. `WatchReminderViewModel` and `WatchReminderView` are unchanged.
- **No StoreKit/entitlement changes**: This is a UI-only feature; no purchase gating, no premium product ID references.
- **No new `Localizable.xcstrings` keys**: Reuse the existing `"Refresh"` key from the Core catalog (`SingleThreadCore/…/Resources/Localizable.xcstrings`) — the same key the watch uses. No app-catalog or watch-catalog changes.

## Open Risks

- **`ContentView.swift` file-length threshold**: The file is near the 650-line `type_body_length` warning (`.swiftlint.yml:29-35`). The refresh button overlay + `#if os(macOS)` block is ~20 lines — should fit, but the implementation phase must verify `make lint` passes. If it pushes over, move the button to a new `ContentView+macOS.swift` extension following the `ContentView+iOS.swift` precedent.
- **MacO S UI test reliability**: MacO S UI tests have no precedent in this project's C I. `platform=macOS` destination may need `CODE_SIGNING_ALLOWED=NO` (as `make mac-test` uses). The test must handle the TCC calendar prompt — the `--seed`/`--ui-testing` seams use `InMemoryEventStore` which reports `.fullAccess` and never triggers a real TCC dialog (`InMemoryEventStore.swift:37`), so seeded tests should avoid TCC issues. Start with a seeded test; fall back to `--ui-testing` if the macOS sandbox interferes with seed injection.
- **`controlPlate()` contrast on macOS window backgrounds**: The adaptive fill logic (`ControlPlateModifier.swift:24-25`) reads the color scheme (`colorScheme == .dark`). On macOS, the window background is `NSColor.windowBackgroundColor` (`Color+CrossPlatform.swift:16-19`). Verify the plate is visible against both light and dark window chrome during implementation — the gear button is already visible (it ships today), so the matching plate should be fine, but confirm.
- **No `app.buttons["refreshButton"]` selector in existing iOS UI tests**: The identifier string `"refreshButton"` already exists in watch UI tests (`SingleThreadWatchUITestsFlows.swift:168,174`). Our macOS test uses the same identifier — no collision risk since watch and macOS tests run in separate C I jobs on separate simulators, but worth noting for grep-ability.
- **Duplicate-tap during minimum-display hold**: The `guard !isRefreshing` drops a second tap silently (same as `WatchReminderViewModel.swift:109`). If user feedback suggests the button should visibly acknowledge rejected taps (e.g., a bounce or flash), that's a follow-up — not in scope for this ticket.
- **`MinimumDisplayDuration` is `nonisolated`**: The `remainingSleep` API is `nonisolated` (`MinimumDisplayDuration.swift:6`), safe to call from `@MainActor` contexts. No concurrency concern.