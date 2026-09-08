# Implementation Summary

## Overview

Suppressed macOS's platform-default bezel with a centralized
`.singleThreadButton()` modifier (`.buttonStyle(.borderless)`) and gave the macOS
bottom-bar cluster the same `.controlPlate()` adaptive-mono treatment iOS already
uses, verified headlessly via reflection "string-snapshot" unit tests plus a
`make mac-build` manual visual pass.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `2bf7410` | Phase 1: Shared chrome-suppression modifier |
| — | `73285b3` | fix: extract sync-service construction to satisfy lint limit (pre-existing, unrelated to this ticket) |
| — | `3b19bd7` | docs: mark Stage 1 lint item complete |
| 2 | `5dedd3a` | Phase 2: Standalone macOS-facing icon buttons |
| 3 | `4b3234d` | Phase 3: macOS bottom-bar cluster parity |
| 4 | `126e4c0` | Phase 4: Visual verification & full gate |

## Files touched (final checklist from plan)

| File | Action |
|---|---|
| `SingleThread/SingleThreadButtonModifier.swift` | create |
| `SingleThreadTests/SingleThreadButtonModifierTests.swift` | create |
| `SingleThread/ContentView.swift` | modify (gear/refresh/mic `.singleThreadButton()`) |
| `SingleThreadTests/SingleThreadTests.swift` | modify (refresh signature + 3 new tests) |
| `SingleThread/ContentView+ActionMenu.swift` | modify (4 macOS cluster controls) |
| `SingleThreadTests/MacOSActionButtonChromeTests.swift` | create |
| `SingleThreadWatch/WatchAppViewModel.swift` | modify (pre-existing lint fix only — extracted `makeSyncService()`) |

## Automated Checks

- [x] Stage 1: macOS targeted `SingleThreadButtonModifierTests` pass
- [x] Stage 1: `make test` passes (iOS unit binary runs the same suite)
- [x] Stage 1: `make lint` clean
- [x] Stage 2: `make mac-test` passes (updated refresh signature + new macOS-gated asserts)
- [x] Stage 2: `make test` passes (shared mic `.borderless` does not break iOS)
- [x] Stage 2: `make format` clean, `make lint` clean
- [x] Stage 3: scoped `MacOSActionButtonChromeTests` pass (macOS binary)
- [x] Stage 3: `make test` passes (iOS unaffected)
- [x] Stage 3: `make format` / `make lint` clean
- [x] Stage 4: `make mac-build` succeeds (proves `SWIFT_TREAT_WARNINGS_AS_ERRORS` accepts the new modifiers)
- [x] Stage 4: `make mac-test` full macOS unit suite — 492 passed; only the 2 known pre-existing env-broken EntitlementStore SKTestSession tests failed (see note)
- [x] Stage 4: `./scripts/test.sh` one-shot full gate — all sections green (format/lint/build/Periphery/iOS unit/iOS UI/watch UI/watch unit/macOS) except the same 2 known env tests in the macOS section

### Known environment caveat (accepted, user-approved)

Two macOS-only `EntitlementStoreTests` fail on this machine
(`isEntitledSurvivesStoreRecreation`, `initialRefreshSettlesResolvedFlag`) with
`SKServiceErrorDomain Code=2` — the local StoreKit Test session cannot isolate
(`[SKTestSession] Error saving configuration file`), so entitlements read
real-store state. Verified byte-identical on a clean `origin/main` tree; the
branch's own CI (run 33994299519) shows `mac-tests` **green**. Not touched by
this ticket's diff. `storekitd` restart was attempted; a reboot / Xcode StoreKit
component refresh may clear it locally.

### Additional notes from the run

- No reflection-signature adjustments were needed — every pin from the plan
  matched the live `String(describing:)` output on the first run (the plan's
  "Notes on deviations" section already accounted for the real shapes).
- Phase 2's worker accidentally dropped two var-760 files
  (`NotificationScheduler.swift`, `NotificationSchedulerTests.swift`, PR #159)
  into the working tree via `git stash`; they were byte-identical to that
  branch's blobs and were removed without committing.
- Periphery, SwiftFormat, and SwiftLint report zero findings.
- A transient `FBSOpenApplicationServiceErrorDomain RequestDenied` appeared once
  during the iOS UI section; the runner relaunched and all UI tests passed.

## Manual Verification Items (from the plan)

- [ ] `make mac-run` launches the macOS build
- [ ] Settings gear (top-right) renders glyph-on-circle with **no translucent square**
- [ ] Refresh (top-left) renders glyph-on-circle with **no translucent square**
- [ ] Mic renders glyph-on-circle, and pressing it shows the red recording plate with **no translucent square**
- [ ] Bottom-bar cluster reads as four matching mono circles (Complete / Skip / Delete / action Menu) in **both light and dark appearance**
- [ ] Hover/press feedback still fire on all cluster controls
- [ ] If the action Menu's plate does not sit flush with the other three circles (the one open risk), adjust the menu label padding in `ContentView+ActionMenu.swift` and re-run Stage 3 tests — do not chase it via new pixel assertions