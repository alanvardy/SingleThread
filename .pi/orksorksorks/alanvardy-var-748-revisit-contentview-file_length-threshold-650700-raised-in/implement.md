# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `83c5ce1` + `469348f` | Phase 1: Previews → ContentView+Previews.swift (incl. checkbox confirm on iOS 26.5 sim) |
| 2 | `f5bf59c`  | Phase 2: iOS notifications extension → ContentView+iOS.swift (incl. early `file_length` disable removal, supervisor-approved) |
| 3 | `bf93a97`  | Phase 3: Settings-bag plumbing → ContentView+Settings.swift (incl. early `type_body_length` disable removal, pre-approved) |
| 4 | `3f5def4`  | Phase 4: Restore threshold (700→650) + remove disables + header rewrite |

Final file layout: `ContentView.swift` **592 lines** (was 817), split into three sibling extensions:
- `ContentView+Previews.swift` (83 lines)
- `ContentView+iOS.swift` (59 lines)
- `ContentView+Settings.swift` (87 lines)

All four commits pushed to `origin/alanvardy-var-748-revisit-contentview-file_length-threshold-650700-raised-in`. Working tree clean.

## Automated Checks

- [x] Phase 1–4: `make build` succeeds (iOS 26.5 simulator, pinned `id=D7AC0D41…`)
- [x] Phase 1–4: `./scripts/test.sh --unit-only` passes — **473 unit tests green** on iOS 26.5
- [x] Phase 1–4: `make lint` returns 0 (SwiftFormat + `swiftlint lint --strict`)
- [x] Phase 4: file_length threshold restored 700→650; **0 violations, 0 serious in 139 files**; `ContentView.swift` has **no** size disables (struct body 563→~488, under the 500 `type_body_length` warning)
- [x] Phase 4 full gate on final tree: format, lint, iOS build, watch build, **Periphery** (clean), iOS unit (473), **watch UI tests**, **macOS build + macOS unit tests** — all green
- [x] Phase 4 full gate — iOS UI suite: **all pass except one known pre-existing failure** — see ⚠️ below (notification UI seams incl. `pendingStatus`/`lastScheduleStatus` under `--ui-testing-notifications` verified passing in the run)
- [x] Line-count checkpoints (apropos): P1 ≈ 737 (plan ≈739), P2 ≈ 678 (plan ≈687), P3 ≈ 594 (plan ≈610), P4 = 592 (plan ≈610) — plan estimates ran ~10 low; block removals were diff-verified exact

## Manual Verification Items (from the plan)

- [ ] Open Xcode, select the canvas for any `#Preview` in `ContentView+Previews.swift` — previews render (build with previews discoverable is verified; actual canvas rendering is a visual check)
- [ ] DECISION NEEDED: `SingleThreadUITestsFlows.testPinWallpaperTogglePersistsAcrossRelaunch` fails on this branch (`0 ≠ 1`, "Pin wallpaper should persist across relaunch") — **pre-existing and out of scope per plan** ("`backgroundPinned`'s missing bag write-back — do not touch"): the write-back chain is byte-identical before/after the moves, and `main` CI's `ui-tests-flows` job fails on the same path. Main's CI also has a failing `watch-ui-tests` job unrelated to these files. Recommend fixing in a separate scoped commit/ticket; the `full gate` checkbox in plan.md stays unchecked until then.

## Notes / observations

- **Simulator runtime artifact**: the 7 `SingleThreadCore` unit failures first seen are an **iOS 26.2 runtime** issue (write/undo/glow suites); the full suite passes on **iOS 26.5** (what CI runs). Pin `SIM='platform=iOS Simulator,id=D7AC0D41-275E-47C5-B603-BC7FA08D1BB4'` locally to match CI.
- **Environment degradation**: the Phase 4 worker timed out at the 30-min subagent cap mid-gate; its uncommitted (verified) changes were inspected, the remaining gate stages (watch UI + macOS) run by the parent, then committed.
- **Superfluous-disable chain**: after the Phase 2/3 splits the file/struct fell below the 700/500 thresholds, so the `file_length` and `type_body_length` disables each became `superfluous_disable_command` violations under `--strict`. Both were removed one phase early (the exact deletions Phase 4 was going to make); plan.md Phase 4 §2 annotated accordingly.
- No new tests: pure code movement. Existing suites are the regression guard.