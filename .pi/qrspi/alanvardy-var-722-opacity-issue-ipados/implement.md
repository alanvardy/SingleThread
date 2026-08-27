# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `e13bc74` | Decision seam (view-model) — `ContentViewModel.rowChromeBackground` + regression tests |
| 2     | `e15d51c` | View paint (presentation) — consume seam in row, `.background(Color.clear)` on List |
| 3     | `f9c039f` | Visual verification + documentation |

## Automated Checks
- [x] `./scripts/test.sh --unit-only` passes (both new `rowBackgroundClear*` seam tests green)
- [x] `swiftformat --lint` + `swiftlint lint --strict` clean on touched Phase 1 files
- [x] `make build` passes (Phase 2; treat-warnings-as-errors on)
- [x] `./scripts/test.sh --ui-only` passes (Phase 2)
- [x] `./scripts/test.sh` full passes — format + lint + build + Periphery green (seam consumed) + unit + UI + watch + macOS (Phase 2)
- [x] `make simverify` passes on iPhone 17 (Phase 3)
- [x] `SIM='platform=iOS Simulator,name=iPad (A16)' make simverify` passes (Phase 3)

## Manual Verification Items (from the plan)
- [ ] On the iPhone simulator, confirm no visible change (plain-list rows were already transparent when no photo is shown).
- [ ] Capture and record light/dark × toggle-on/off screenshots on both `iPad (A16)` and `iPhone 17`; confirm the plate gate (`showsOverPhoto`) and the always-clear row match the documented expectations (see `docs/SimulatorManualVerification.md`, "Container opacity (VAR-722)").
- [ ] Confirm on a physical iPad if available (simulator vs. hardware has diverged for list backgrounds historically).