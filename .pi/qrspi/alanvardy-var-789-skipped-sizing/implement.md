# Implementation Summary

Ticket: **var-789 — Skipped sizing** (iPad card stretch + oversized sheets)

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `2fcaf94` | Pure width-cap helper (`CardWidth`) + delegation from `EmptyStateCard` + `CardWidthTests` |
| 2     | `db8f29e` | Card de-stretch + width cap (reminder card view layer): `maxWidth` cap in `ReminderCardView`, nudge-banner content-hug, swipe-prompt frame removal, viewport cap passed from `ContentView` |
| 3     | `a1ef12f` | Content-sized sheets (sheet view layer): `.presentationDetents([.height(...)])` fallback applied after `presentationSizing(.fitted)` regressed the iPad nudge-sheet taps |

Phase 4 (full gate) produced no source changes — verification only, see below.

## Automated Checks

- [x] `make format` / `make lint` clean (SwiftFormat + SwiftLint `--strict`, 0 violations)
- [x] `make build` passes (iOS, iPhone 17 + iPad A16)
- [x] `CardWidthTests` green (4/4: below-ceiling scaling, ceiling pin, boundary, non-negative at zero)
- [x] Red-first requirement — **not reproducible, adjudicated**: the pre-added `testNudgedCardDoesNotSpanRowOnIPad` passes on pre-fix code because `origin/main` commit `0e3b49e` already content-hugged the nudge banner (measured: window 820pt, banner 148pt pre-fix). The genuinely-stretching states were long-title (616pt) and the swipe prompt. Test retained as a post-fix regression guard; red-first checkbox left unchecked with a documented note.
- [x] iPad after-fix: `testNudgedCardDoesNotSpanRowOnIPad` + full `SkipNudgeUITests` + `ActionMenuUITests` green (independent re-verification by parent)
- [x] iPhone regression: `SkipNudgeUITests`, `ActionMenuUITests`, `SingleThreadUITestsFlows` green; full `SingleThreadUITests` 51/51 green
- [x] `make test` (iOS unit) green — `String(describing:)` card snapshot suites (`ShowDateTests`, `ShowAlarmsTests`, `ShowRecurrenceTests`, `SwipePromptTests`) unaffected
- [x] `make periphery` clean (all phases)
- [x] Phase 3 sheet presentation: `presentationSizing(.fitted)` implemented first per plan → regressed iPad nudge-sheet taps (`nudgeDeleteButton`/`nudgeViewInRemindersButton` hit point `{-1,-1}` — clipped by the fitted sheet's height; pre-change passed) → plan's documented fallback applied: `.presentationDetents([.height(320)])` reschedule / `.height(420)` nudge. iPad + iPhone suites green after the swap.
- [x] Full gate (`./scripts/test.sh`): swiftformat → swiftlint `--fix`/`--lint`/`--strict` → iOS build → watch build → periphery → iOS unit (609 passed / 0 failed) → iOS UI (51/51) → watch UI + watch unit (`TEST EXECUTE SUCCEEDED` ×2) — all green
- [ ] **macOS unit: 489/491 — 2 `EntitlementStoreTests` fail on this host only** (environment, not our diff). Evidence: (1) identical failure on a clean `origin/main` worktree; (2) CI `mac-tests` job green on `origin/main` (run 33993949555); (3) same tests passed on this machine in the var-780 gate; (4) `SKTestSession` reports `SKServiceErrorDomain Code=2` saving config on this host; (5) an in-test `clearTransactions()` makes the two pass in isolation, and the full suite re-creates the leak with no purchase/`AppStore.sync` calls anywhere in the suite — host StoreKitTest/storekitd sandbox state. Suggested follow-ups: reset host sandbox account; keep macOS tests serial in CI. See full note in `plan.md` Phase 4.

## Manual Verification Items (from the plan)

- [ ] `EmptyStateCard` still renders identical empty/all-done cards (behavior-preserving refactor)
- [ ] On iPad sim: card hugs content in all four states (plain / nudge banner / swipe prompt / long title) — never edge-to-edge; on iPhone the card looks unchanged except long titles wrap at the cap
- [ ] On iPad sim: tap the nudge banner — sheet is content-sized (no blank bands); open the action-menu Reschedule sheet — also content-sized; Cancel and the `DatePicker` both render and dismiss correctly
- [ ] Optional (skip if it trips local-only hit-region flakiness): assert the sheet content VStack frame is narrower than the screen on iPad
- [ ] Confirm watch and Today-widget still render their cards centered and hugged (sanity spot-check, no regression expected)

## Observations / Mismatches Adjudicated

1. **Red-first premise falsified (Phase 2)** — the plan expected the nudged banner to stretch on iPad pre-fix, but `origin/main` `0e3b49e` already hugged it. Proceeded with steps 1–4 as planned (they fix the real stretch sources: swipe prompt, long titles, and future-proof the nudge banner); kept the test as a regression guard. Option to strengthen the committed iPad test toward the swipe-prompt state is available in review if desired.
2. **`.presentationSizing(.fitted)` regressed iPad tap targets (Phase 3)** — the plan's named open risk (Decision 3) materialized as button clipping rather than toolbar/DatePicker misbehavior. Applied the plan's documented detent fallback with the plan's exact per-sheet values. `fitted` remains the preferred end state if the sheet layout is later made fully huggable; the detent values are content-appropriate (320/420) but are fixed heights — a future `fitted`-compatible layout (e.g. removing the top-anchored stretch) would be cleaner.
3. **macOS StoreKit env failure (Phase 4)** — see Automated Checks. Not caused by, or fixable within, this ticket.
4. Phase 2's worker timed out mid-verification (unit tests); the parent completed the remaining checks (unit tests, periphery, plan.md checkboxes, commit). Phase 3's worker finished within budget. No commits were left dangling; the working tree is clean.