# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `521f98c` | Cross-platform image bridge + view refactor |
| 2     | `dec20d3` | Render integration (un-gate ContentView) |

## Automated Checks
- [x] `make format` then `make lint` (SwiftFormat + SwiftLint `--strict` clean)
- [x] `make test` — iOS unit suite green (incl. new `BackgroundPhotoLayerTests`)
- [x] `make mac-test` — macOS unit suite green (proves `NSImage` bridge passes on macOS)
- [x] `make periphery` — Periphery `--strict` clean
- [x] `make mac-build` — ungated instantiation compiles on macOS
- [x] Full `./scripts/test.sh` gate (final, by parent): format, lint, build, Periphery, iOS unit + UI, watch unit + UI, macOS unit — **all green**

## Manual Verification Items (from the plan)
- [ ] **Phase 1 (optional):** iOS simulator — photo still renders behind the reminder card identically to before (this stage is behavior-neutral on iOS).
- [ ] **Phase 2 — `make mac-run`:** macOS app launches and the photo renders **behind** the reminder card (not over it).
- [ ] **Phase 2:** Fade `Picker` (Settings → Background) changes the photo opacity visibly.
- [ ] **Phase 2:** Pin toggle keeps the current photo (skip refresh) across relaunch.
- [ ] **Phase 2:** Disabling the background `Toggle` hides the photo (returns to `Color.systemBackground`).
- [ ] **Phase 2:** Fresh / no-cached-photo state shows only the system background (no crash, no layout shift).
- [ ] **Phase 2 (Open Risk 1):** Photo does not render in a visually broken way behind the titlebar / traffic-light buttons — document the result in the PR.

## Observations & Notes
- The `image(from:)` bridge is the testable unit (valid JPEG → non-nil; garbage → nil). Pixel-level render "look" is deferred to the manual macOS check — un-stubbable headlessly by design.
- `ContentView.swift` ZStack order unchanged (`Color.systemBackground` → photo layer → content).
- No store/fetch/prefs/settings code changed — those were already shared and CI-green on macOS.
- History note: Phase 1's push required a `--force-with-lease` because `origin` held stale rewritten copies of this ticket's base commits built on an older `origin/main`; remote now points cleanly at the rebased lineage `5ac5f2c → 85ff050 → 521f98c → dec20d3`. No work lost.