# Design Discussion — Pin Wallpaper (VAR-743)

## Current State

Background photo auto-refreshes every 24h via `refreshIfNeeded(maxAge:)`
(`BackgroundImageStore.swift:91-99`), triggered once on first render by a
`.task` in `ContentView.swift:88-90`. The user can manually pull a random
photo from Settings via `forceRefresh()` (`BackgroundSettingsView.swift:26`).
No mechanism exists to suppress the auto-refresh without also disabling the
background entirely (the existing `backgroundEnabled` toggle only hides the
rendered layer, `ContentView.swift:165-166`).

Two `@AppStorage("…", store: .standard)` keys govern background display
(`ContentView.swift:165-169`); both flow through the five-step settings pipe
(`@AppStorage` → `SettingsBindings` (:26-27) → `makeSettingsBag()` (:545-546,
:559-560) → `.onChange` writeback (:129-130) → Toggle/Picker in
`BackgroundSettingsView.swift:16-22`). Photo bytes and sidecar metadata live
on disk (`background.jpg`/`background.json`), intentionally phone-local —
never App Group or sync payloads (`BackgroundImageStore.swift:50-52`,
`SkippedReminderSyncService.swift:167-222`).

## Desired End State

A "Pin wallpaper" toggle in the Background settings section. When enabled:

- **`refreshIfNeeded` is gated** — the store checks the pin before fetching; a
  pinned wallpaper is treated as perpetually fresh, regardless of sidecar
  `fetchedAt`. No auto-refresh, no matter how old the photo.
- **`forceRefresh` (manual) always works** — the user can still pull a new
  photo from the "Refresh wallpaper" button while pinned. The pin survives
  manual refresh (it's about auto-refresh behavior, not a specific photo).
- **Unpinning triggers `refreshIfNeeded`** — when the user toggles the pin off,
  the store immediately checks freshness. If the photo is stale (≥24h), a new
  one fetches automatically. If still fresh, nothing happens.

Toggle lives in its own `Section` in `BackgroundSettingsView`, visible only
when `backgroundEnabled == true`.

Verification: unit tests for the new gating logic (pin blocks `refreshIfNeeded`,
unpin triggers freshness check, `forceRefresh` ignores pin); UI test for
toggle persistence across relaunch following the same `--seed`/`--ui-testing`
pattern used by `testBackgroundToggleHidesAndPersistsAcrossRelaunch`
(`SingleThreadUITestsFlows.swift:198-232`).

## Patterns to Follow

1. **Five-step settings pipe** — any new `@AppStorage` boolean follows the
   exact path mapped by `backgroundEnabled`: declare `@AppStorage(key, store: .standard)`
   with a default in `ContentView.swift:165-166` → add a `var` with a defaulted
   init param in `SettingsBindings.swift:26` → snapshot the live value in both
   `makeSettingsBag()` branches (`ContentView.swift:545-546, :559-560`) → write
   back via `.onChange(of: bag.x)` (`ContentView.swift:129-130`) → bind to a
   `Toggle` in `BackgroundSettingsView`.

2. **Behavior lives in `BackgroundImageStore`** — the store already owns all
   refresh logic (`refreshIfNeeded` :91, `forceRefresh` :107, `isFresh` :178);
   the pin state should be consulted there, not in view code. Views only
   pass the toggle binding.

3. **`private(set)` observable state** — any new observable property follows
   the existing pattern (`BackgroundImageStore.swift:69-76`): `private(set)`
   with public read-only access, mutated only inside methods.

4. **Test with injected fake fetcher + temp dir** — reuse
   `FakeBackgroundFetcher` (`BackgroundImageStoreTests.swift:254-263`), the
   1×1 JPEG fixture (`BackgroundTestFixtures.swift:10-23`), and UUID temp
   directory injection pattern (`BackgroundImageStoreTests.swift:328-335`).

5. **UI test persistence with `--ui-testing` relaunch** — `--seed` wipes all
   persisted keys (`UITestingSeed.persistedKeys`, `UITestingSeed.swift:56-75`)
   so cross-relaunch tests relaunch with `--ui-testing` instead
   (`SingleThreadUITestsFlows.swift:216-220`). Add `"backgroundPinned"` to
   `persistedKeys` alongside the existing `backgroundEnabled` (and the missing
   `backgroundFadePercent`).

**Patterns NOT to follow:**

- **No `BackgroundPreference` struct in `SingleThreadCore`** — the existing
  background keys are phone-local `.standard`; introducing the Core
  preference-struct pattern (`ShowAlarmsPreference.swift:8`) for this one-off
  adds indirection without benefit. Keep it consistent with `backgroundEnabled`.
- **No cross-target propagation** — background state is intentionally
  phone-local (`BackgroundImageStore.swift:50-52`); the widget and watch have
  zero references to background keys (research Q6). The pin stays in `.standard`.
- **No platform `#if` guard** — macOS Background Settings compiles and renders
  the same rows as iOS (research Q6); the pin toggle compiles on macOS even
  though `BackgroundPhotoLayer` is iOS-only. No change needed.

## Design Decisions

1. **Storage: `@AppStorage("backgroundPinned", store: .standard)` with default `false`** — matches the two existing background keys' tier, keeps the five-step pipe uniform, and requires no new persistence abstraction. The pin is a display preference, not photo metadata, so sidecar storage (`Option B`) is semantically wrong and would couple pin lifecycle to disk state.

2. **Pin blocks `refreshIfNeeded` only; `forceRefresh` always works** — "pin" means "don't change on its own" (the task description). Manual refresh is an explicit user action. Blocking it would create an unpin→refresh→re-pin friction loop if the user wants a fresh pinned wallpaper.

3. **Unpin triggers `refreshIfNeeded`** — gives immediate visual feedback if the photo is stale, matching the user's intent ("I just unpinned — show me what I've been missing"). No forced network fetch if the photo happens to still be fresh (≤24h).

4. **Toggle in its own `Section`, visible only when `backgroundEnabled`** — separates "auto-refresh behavior" from "display appearance" (enable/fade), and hides the control when it has no effect (background off means nothing to pin). Follows the existing Section pattern at `BackgroundSettingsView.swift:24-37` (refresh button already has its own Section).

5. **Manual refresh preserves the pin** — pin is about auto-refresh behavior, not about freezing a specific photo. If the user manually refreshes to a new wallpaper they like, the pin should keep it from auto-rotating away. To resume auto-rotation, they unpin explicitly.

## What We're NOT Doing

- **Not blocking `forceRefresh`** — design decision #2.
- **Not clearing pin on manual refresh** — design decision #5.
- **Not changing the 24h freshness window, the two endpoints, or the fetch mechanics** — this is purely additive gating.
- **Not propagating the pin to widget or watch** — no background key crosses the App Group boundary; no reason to start now.
- **Not adding a timer or `scenePhase`-based refresh trigger** — `refreshIfNeeded` stays lifecycle-triggered (`ContentView.swift:88-90`), just now conditionally skipped.
- **Not adding a macOS-specific UI branch** — the toggle compiles and renders on macOS like the existing Background rows; no harm, no platform guard.

## Open Risks

- **No mutual exclusion between `refreshIfNeeded` and `forceRefresh`** (pre-existing). A concurrent manual refresh + unpin-induced `refreshIfNeeded` could race. Both only mutate on success and `@MainActor` serializes access; low practical risk, and fixing it is scope creep.
- **`persistedKeys` gap**: `backgroundFadePercent` is missing from `UITestingSeed.persistedKeys` (existing bug — survives `--seed` wipes). We'll add `backgroundPinned`; should also add `backgroundFadePercent` to fix the gap, or document it as known.
- **macOS behavior**: toggle compiles and renders but has no visible effect since `BackgroundPhotoLayer` is iOS-only. Consider adding a `.disabled` modifier or explanatory footer text on macOS if it causes confusion — otherwise, match existing pattern (the enable/fade controls similarly do nothing visible on macOS).