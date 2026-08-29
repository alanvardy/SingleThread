# Implementation Summary

Swipe-instruction prompt for the reminder card ("← Swipe left to skip | Swipe right to complete →" + Dismiss button), gated by an iOS-only `@AppStorage("showSwipePrompt")` boolean (default on) with an Interface Settings toggle.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| chore | e736c3a | QRSPI design + plan artifacts |
| 1     | b6d753f | Persistence + bindings + test infrastructure for showSwipePrompt |
| 2     | 4d8508b | Show swipe prompt settings toggle |
| 3     | e2a8156 | Swipe-prompt card view with dismiss |
| 4     | 645540e | Swipe-prompt UI tests + accessibility audit |

## What Was Built

- **Phase 1** — `SettingsBindings.showSwipePrompt` (default `true`), iOS-only `@AppStorage` in `ContentView`, `.onChange` write-back in the settings sheet, `makeSettingsBag()` iOS branch, `UITestingSeed.persistedKeys` entry, plus unit tests for the bindings bag and persistence reset.
- **Phase 2** — "Show swipe prompt" toggle in Interface Settings (`#if os(iOS)`), wired through `SettingsView` → `InterfaceSettingsView`; preview + `SettingsViewTests` updated.
- **Phase 3** — `ReminderCardView` gains `showSwipePrompt: Binding<Bool> = .constant(false)`; prompt (accessibility-hidden text) + Dismiss button render below the notes; new `SwipePromptTests` (3 tests); existing test helpers compile unchanged via the default.
- **Phase 4** — three UI-test flows (appears under `--ui-testing`; Dismiss persists across relaunch; Settings toggle round-trips), accessibility audit kept green, full `./scripts/test.sh` gate passes.

## Deviations From Plan (all verified against the real codebase)

1. **`--ui-testing` seam (Phase 1 → 4 interplay)**: the plan's unconditional `UserDefaults.standard.set(true, forKey: "showSwipePrompt")` would re-enable the prompt on every `--ui-testing` relaunch and break the Phase 4 persistence test. Replaced with a `--reset-swipe-preference` removal flag mirroring the existing `--reset-glow-preference` seam; UI tests pass it on their first launch only.
2. **Prompt placement outside the combined accessibility element (Phase 3)**: the plan's literal placement (inside `.accessibilityElement(children: .combine)`) would swallow the Dismiss button from VoiceOver/XCUITest. The card content keeps `.combine`; the prompt + button live outside it.
3. **Call-site binding (Phase 3)**: `Content`'s `ReminderCardView` call site is not `#if os(iOS)`-gated and the app builds for macOS, so `$showSwipePrompt` cannot be passed unguarded (and `#if` is illegal inside a function-call argument list). Added a private `swipePromptBinding` computed property (`$showSwipePrompt` on iOS, `.constant(false)` elsewhere).
4. **Unit-test label assertion (Phase 3/4)**: `String(describing:)` cannot see accessibility label *strings* (repo-documented). The test asserts the `AccessibilityAttachmentModifier` presence; the label value is asserted by the Phase 4 UI test via `app.buttons["Dismiss swipe prompt"]`.
5. **Hit-region audit (Phase 4)**: the caption-sized Dismiss button's AX frame was ~14pt and failed the local `hitRegion` audit (CI only audits cheap categories, so it passed there). Fixed with button-level `.padding(.vertical, 15)` + `.contentShape(Rectangle())` — label-content padding does *not* expand the AX frame; button-level padding does (frame is now 44×44.3pt). Verified with a temporary diagnostic UI test (removed before commit).
6. **Pre-existing test fix (Phase 4, out of plan scope)**: `SingleThreadUITestsFlows.testSettingsOpensAndShowsControls` was already failing on `origin/main` — it tapped `"Privacy"` but the Settings row is labeled `"Privacy Policy"` (verified failing identically at `0d5e381` on GitHub Actions and via a worktree run at `origin/main`). The test now uses the correct label; this was required for the gate.

## Automated Checks

- [x] SettingsViewTests + UITestingSeedTests (Phase 1)
- [x] SettingsViewTests (Phase 2)
- [x] SwipePromptTests (Phase 3)
- [x] Full `SingleThreadTests` suite (Phase 3)
- [x] iOS Debug build without warning/error (Phase 3)
- [x] `SingleThreadUITestsFlows` — 18 flow tests including 3 new swipe-prompt tests (Phase 4)
- [x] `SingleThreadUITests.testAccessibilityAudit` — full local audit (dynamicType, hitRegion, element description, trait) (Phase 4)
- [x] `./scripts/test.sh` end-to-end: format, SwiftLint --strict, iOS build-for-testing, watch build, Periphery --strict, 804 unit+UI tests (0 failures), watch UI tests, macOS build + unit tests (Gate Check)

## Manual Verification Items (from the plan)

- [ ] Build & run on simulator → Settings → Interface, confirm "Show swipe prompt" toggle appears, defaults ON
- [ ] Build & run on simulator → prompt appears below notes on the card
- [ ] Tap Dismiss → prompt disappears
- [ ] Relaunch → prompt stays gone (persisted via `@AppStorage`)
- [ ] Build & run on simulator, verify prompt → Dismiss → Settings toggle round-trip all work visually
- [ ] Run VoiceOver, verify the card reads normally (prompt text not spoken) and Dismiss button is reachable

## Notes for Review

- The watch app is untouched (iOS-only preference, as designed; no `Show*Preference` struct, no `SingleThreadCore` API).
- `Row height + bottomBar overlap` risk from the design doc: with the prompt visible the card grows ~60pt; under `--ui-testing` (empty body with prompt) the card and the bottom bar coexist without overlap in the UI tests, but a large-Dynamic-Type + long-notes check is worth a manual look.
- The `DELETEME` scaffold artifact at the repo root is removed in the summary commit, matching prior branches.