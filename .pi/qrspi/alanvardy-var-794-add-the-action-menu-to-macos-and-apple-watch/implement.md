# Implementation Summary

Ticket: var-794 — Add the action menu to macOS and Apple Watch
Branch: `alanvardy-var-794-add-the-action-menu-to-macos-and-apple-watch`

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `17f8136` | Storage — ungate `@AppStorage` declaration (`enableActionButtons` out of `#if os(iOS)` in `ContentView.swift`) |
| 2     | `0419d7a` | Settings plumbing — wire bag construction + write-back on macOS (`ContentView+Settings.swift`, plus the forced `@Binding` ungate in `InterfaceSettingsView.swift` + preview test call-site fix, see notes) |
| 3     | `69fa85b` | UI — "Show action buttons" toggle row moved to unconditional in `InterfaceSettingsView.swift` + two macOS-gated tests |
| 4     | `4ea0da9` | Full gate — `./scripts/test.sh` end-to-end green except the two documented host-local `EntitlementStoreTestsFailures`; plan.md checkbox + env note committed |

## Automated Checks

- [x] SwiftFormat pass 1 + lint — 0/165 files changed
- [x] SwiftLint `--strict` — clean
- [x] iOS build (`build-for-testing`) — success
- [x] Watch build — success
- [x] Periphery `--strict` — no unused code
- [x] iOS unit tests — `TEST EXECUTE SUCCEEDED`
- [x] iOS UI tests — 51/51 `TEST EXECUTE SUCCEEDED` (one flake `testNoScheduleWhenNoReminders` passed in serial isolation + parallel re-run)
- [x] Watch UI tests — `TEST EXECUTE SUCCEEDED`
- [x] Watch unit tests — `TEST EXECUTE SUCCEEDED`
- [x] macOS unit tests — 495 passed incl. all **4 new mun macOS-gated tests** for this ticket; 2 failures = pre-existing host-local `EntitlementStoreTests` (below)
- [x] The four new macOS tests pass: `macOSBagIncludesEnableActionButtons`, `macOSEnableActionButtonsRoundTripsThroughAppGroup`, `interfaceSettingsViewContainsActionButtonsRowOnMacOS`, `macOSToggleTogglesBinding`

**Host-local environment failure (not our diff, documented in plan.md):** `EntitlementStoreTests.isEntitledSurvivesStoreRecreation` + `initialRefreshSettlesResolvedFlag` fail on this machine due to a StoreKitTest/storekitd sandbox leak (`SKServiceErrorDomain Code=2` saving config). Proven pre-existing: identical failure on a clean `origin/main` worktree, CI mac-tests green on `origin/main`, same failure documented in var-789. Do not treat the macOS unit leg as fully green on this machine until the StoreKit sandbox is reset. Opened/noted as a follow-up; out of scope for this ticket.

## Plan adjustments made during implementation

- **Phase 2 fold-in (supervisor-authorized):** Stage 2 change #3 (`SettingsView.swift` passing `enableActionButtons:` to the `InterfaceSettingsView` memberwise init) cannot compile unless Stage 3 change #1 (ungating the `@Binding var enableActionButtons`) lands first — Swift's memberwise init requires the parameter to exist unconditionally. Phase 2 therefore also ungated the `@Binding` in `InterfaceSettingsView.swift` and the pre-existing macOS branch of `interfaceSettingsViewContainsExpectedRows` in `SettingsViewTests.swift` plus the macOS `#Preview` call site (all forced by the same coupling). Phase 3 then verified those were in place and completed only the Toggle row + Stage 3 tests.
- **Test adaptation:** the plan's `macOSToggleTogglesBinding` snippet used `Binding(wrappedValue: false)`, which does not compile on this toolchain (Swift 6). Adapted to `Binding(get: { false }, set: { _ in })` — same intent, compiles clean.
- **Docs kept truthful:** `InterfaceSettingsView.swift` doc comment updated (`orientation + action button toggles` → `orientation, swipe-prompt, and undo toggles`) since "action button" is no longer platform-gated.

## Manual Verification Items (from the plan)

- [ ] macOS app builds and launches — no visible change on Stage 1 baseline (flag defaults to `false`)
- [ ] iOS app builds and runs — toggle row still present in Interface settings, functional
- [ ] macOS app: gear icon → Interface section → "Show action buttons" toggle is visible
- [ ] Toggle ON → close sheet → bottom bar shows action menu (3-dot `Menu` with Skip/Reschedule/Delete)
- [ ] Toggle OFF → close sheet → bottom bar shows direct Skip + Delete buttons
- [ ] iOS app: toggle row still present and functional (no regression)
- [ ] macOS: settings sheet → toggle ON → bottom bar switches to action menu; toggle OFF → direct buttons
- [ ] iOS: toggle row unchanged, action menu/direct skip still work
- [ ] Watch: sync delivers the flag (toggle on iOS/macOS → watch receives within ~5s) — action menu confirmation dialog appears when enabled
- [ ] Keyboard shortcuts: `c` (complete), `s` (skip/menu), `delete` (delete) all work regardless of toggle state

## Follow-ups noted by workers (out of scope, not acted on)

- Host StoreKit sandbox state causes the 2 macOS `EntitlementStoreTests` failures on this machine — reset the sandbox account or pin macOS tests serial in CI.
- Concurrent sim use: a separate repo (var-796) ran iOS tests on the same base simulator during Phase 4; phase completed without impact, but a shared-machine CI/sim lock may be worth considering.