# Implementation Summary

Ticket: [alanvardy-var-781-sort-reminders-by-list] — Sort reminders by list
Branch: `alanvardy-var-781-sort-reminders-by-list` — PR #160 (draft)

After the user-selected primary sort (priority, due date, or title), reminders are grouped by their list (calendar title) via a new `compareLists` comparison tier threaded into all three option chains in `ReminderSort`. Pure, stateless ordering function in `SingleThreadCore` — every surface (iOS, watchOS, macOS, widget) inherits it through `ReminderStore.visibleReminders`.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 0     | 5fa08ab | chore: structure for alanvardy-var-781-sort-reminders-by-list (pre-existing) |
| 1     | 5352c2f | Phase 1: test seam — list-bearing fixture (`makeReminder(calendarTitle:)`) |
| 2     | c454446 | Phase 2: comparator — `compareLists` tier + chain threading (production change) |
| 3     | 1879004 | Phase 3: fix line length in `nilListSortsLast` assertion (ticket-attributable lint catch) |
| 3     | 1e0fe3d | Phase 3: record periphery pass; document pre-existing watch lint blocker |
| 3     | e56be45 | fix: extract `wireStoreSyncHooks` to clear pre-existing lint violation on main (user-approved scoped fix) |
| 3     | c401bf3 | Phase 3: full gate passes end-to-end (plan.md checkboxes) |

## Automated Checks

- [x] `./scripts/test.sh --unit-only` passes (Phase 1: seam compiles, existing `ReminderSortTests` green with default-`nil` fixtures)
- [x] `./scripts/test.sh --unit-only` passes (Phase 2: all six new list-grouping cases + every pre-existing unmodified chain test)
- [x] `make periphery` clean — "No unused code detected"; `compareLists` wired into all three chain arms
- [x] `./scripts/test.sh` full end-to-end gate (SwiftFormat → SwiftLint --strict → iOS build-for-testing → watch build → Periphery → iOS unit → iOS UI → watch build-for-testing → watch UI → watch unit → macOS unit) — **all stages PASS except 2 pre-existing macOS-only StoreKit-sandbox entitlement tests** (see caveat below)

### Caveats / pre-existing issues encountered (all verified not attributable to this branch, per AGENTS.md)

1. **SwiftLint `function_body_length` in `SingleThreadWatch/WatchAppViewModel.swift`** — pre-existing breakage introduced on main by `077e3b8` (platform action menus); was failing main's own CI. Fixed on this branch by user decision in a scoped commit (`e56be45`, minimal mechanical extraction mirroring the existing `wireStateReceiveHooks` pattern, no behavior change). Should be reconciled on main (the same scoped fix should land there or via this PR's merge).
2. **2 macOS unit tests fail only on this Mac** — `EntitlementStoreTests.isEntitledSurvivesStoreRecreation` / `initialRefreshSettlesResolvedFlag`: this Mac's StoreKit sandbox account resolves `isEntitled=true`, which the tests assume absent. Same tests pass on iOS sim in the same gate run; CI `mac-tests` is green on origin/main; test file byte-identical to origin/main; branch diff touches zero entitlement/storekit code. To see them green locally: reset the local StoreKit sandbox/purchase state (`xcrun simctl` erase / StoreKit sandbox account reset per the `storekit` skill) — no code change warranted.
3. **Gate run environment collisions** — the user's own `ZzWidthDiagnosticUITests` / `SkipNudgeUITests` diagnostic loop on the iPad sim shared the repo-root `DerivedData`; the gate was run with an isolated `/tmp/p3-gate-DerivedData` copy of `scripts/test.sh` to avoid corrupting either build. Two collisions occurred and were waited out per protocol; the third attempt ran clean. No user processes were killed. The repo's `scripts/test.sh` was not modified.

## Manual Verification Items (from the plan — do not check off without user confirmation)

- [ ] Phase 1: confirm no fixture outside `ReminderSortTests` is affected — grep `makeReminder(` call sites in `SingleThreadTests/`, none pass a 4th argument (all compile against the defaulted parameter)
- [ ] Phase 2: confirm the three switch arms each invoke `compareLists` exactly once, in the prescribed position (primary → list → secondary → title/`false`)
- [ ] Phase 2: confirm the legacy 2-arg comparator is untouched and still delegates to `using: .priority`
- [ ] Phase 3: PR description contains the UI-gap statement (below), verbatim or equivalent
- [ ] Phase 3: confirm `make format` (`organizeDeclarations`) left no pending formatting diff and `swiftlint lint --strict` is clean

### PR UI-gap statement (Phase 3.2 — include in PR body)

> List grouping is unit-tested only; a deterministic list-grouping UI flow requires the deferred `--seed` per-calendar extension (`UITestingSeed.swift:145,153` forces the first calendar on every reminder). No `--seed` schema change was made in this ticket (per design Decision 4), so no UI test exercises list grouping.

## Notes for review

- No deviations from `structure.md`; phase order, file scope, and the bottom-up shape (fixture seam → comparator → full gate) preserved exactly.
- Observations recorded by implementers but intentionally NOT changed (out of scope): none beyond the two pre-existing caveats above.
- The `--unit-only` gate missed the Phase 2 line-length lint catch (`nilListSortsLast` assertion); the full gate's SwiftLint --strict caught it. Noted for future plans: run `swiftlint lint --strict` on touched files in the unit-only loop.