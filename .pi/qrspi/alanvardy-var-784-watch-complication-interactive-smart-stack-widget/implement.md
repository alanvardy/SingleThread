# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `3868826` | Shared widget-state derivation (Core) |
| 2     | `d551dec` | Watch widget extension target + App Group plumbing |
| 3     | `d69b21e` | Mutation dispatch + mailbox drain |
| 4     | `5895d0d` | Watch widget surface (bundle, provider, accessory views) |
| 5     | `3d1cd29` | Refresh lifecycle + full gate |

## Automated Checks

All automated verification items from `plan.md` are checked (`- [x]`):

- **Phase 1** — `ReminderWidgetStateTests` (6 tests, iOS + macOS): `make test` ✓ · targeted suite ✓ · `make build` ✓
- **Phase 2** — `make watch-build` ✓ (new `SingleThreadWatchWidget` target compiles and embeds into `SingleThreadWatch.app`) · deployment-target guard `22` (8+6+8) ✓ · `plutil -lint` OK + `xcodebuild -list` shows target ✓ · `make watch-test` ✓
- **Phase 3** — `make test` ✓ (`PendingReminderActionTests` codec + store, 4 tests) · `make watch-test` ✓ (`PendingActionDrainTests`, 3 tests + existing watch suites)
- **Phase 4** — `make watch-build` ✓ (.appex rebuilt + embedded) · Phase 1 + 3 suites still green ✓
- **Phase 5** — full `./scripts/test.sh` **GATE_EXIT=0, "✅ All CI checks passed"** (format, SwiftFormat, SwiftLint, build iOS/watch/mac, deployment-target guard, Periphery "No unused code detected", unit + UI + watch suites) ✓ · `make periphery` ✓ · `make lint` ✓

Full-gate evidence: `/tmp/p5-gate.log` (`GATE_EXIT=0`).

## Manual Verification Items (from the plan)

- [ ] **Phase 1** — iOS widget still renders the same four states on the home screen (no-access lock, empty, all-done, reminder card) — no visual diff.
- [ ] **Phase 2** — `xcrun simctl get_app_container <booted-watch-UDID> app.alanvardy.SingleThread.watchkitapp app` shows `SingleThreadWatchWidget.appex` inside `PlugIns/`.
- [ ] **Phase 3** — (deferred to Phase 4's smoke test — mutations can't be exercised until the Smart Stack buttons exist.)
- [ ] **Phase 4** — Complication renders all four states on a watch face (boot a watch sim via `xcrun simctl`; add the complication).
- [ ] **Phase 4** — Smart Stack shows the widget with Complete/Skip buttons.
- [ ] **Phase 4** — Tapping a button opens the watch app (drains + relays) and the reminder leaves the list.
- [ ] **Phase 5** — Complete/skip a reminder in the watch app → complication refreshes promptly (no 15-min wait).

## Deviations & Observations (for review)

1. **Bundle identifier** (Phase 2, planned value): the plan's `app.alanvardy.SingleThread.watchwidget` fails Apple's embedded-binary validation — the widget's bundle id must be prefixed with the parent app's id (`app.alanvardy.SingleThread.watchkitapp`). Implemented as **`app.alanvardy.SingleThread.watchkitapp.watchwidget`** (allowed by design.md decision 1's "exact suffix confirmed at implementation"). Use it for the manual `simctl get_app_container` check.
2. **Process deviation (Phase 5)**: the Phase 5 subagent timed out mid-gate; its `nohup`'d gate died with it, and a sibling worktree's gate (VAR-787) briefly contended for the shared simulators (the cause of the earlier `RequestDenied` launcher failures in that run — one xcodebuild test at a time). The parent re-ran the single full gate after the simulators freed and it passed. The Phase 5 code diff was inspected end-to-end before committing.
3. **`wireMutationHooks` extraction** (Phase 5): the mutation relay hooks were moved into a private helper so `setupSyncService` stays within SwiftLint's 50-line function-body limit. Behavior identical to the plan's inline snippet (verified by the full gate).
4. **SwiftFormat normalizations** (Phases 1/3): the codebase's SwiftFormat/SwiftLint config rewrites some plan literals (`settle: { })` → trailing closure, `case .empty(let hasHidden)` → `case let .empty(hasHidden)`, `@Suite` dropped). Compiles and lints clean; tests all pass.
5. **Known UI-test gap (state in PR body)**: actual widget rendering and the tap → `openAppWhenRun` → app → relay handoff are not XCUITest-drivable (the widget process is not system-launch-testable). Every logical link one layer down is unit-green: `makeWidgetState` (Phase 1), mailbox codec + drain/relay (Phase 3), refresh reloads (Phase 5). Only the Phase 2/4/5 manual simulator smoke items cover the top layer.
6. **App Group + storage shift (flag in PR)**: once the App Group suite is registered on watchOS, `AppGroup.defaults` stops collapsing to `.standard`, so watch-side skips/exclusions/sort reset once and re-sync from the phone on the next WatchConnectivity exchange. No migration code by design.
7. **Periphery index-store caveat**: Periphery scans the build's index store; stale records from incremental Phase 4 builds produced a false positive during Phase 5 staging. A clean rebuild of the widget target cleared it; green in the final gate.