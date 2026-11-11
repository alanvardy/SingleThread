# Implementation Summary

Branch: `alanvardy-var-1170-increase-width-on-outer-duo-screen`
Plan: `plan.md` (all phases complete; Phase 1 + Phase 2 Automated checkboxes ticked)

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `38da945d` | Phase 1: Duo outer portrait widens the reminder card end-to-end |
| 2     | `e1af721f` | Phase 2: Empty states and the AI-sort banner follow the same policy |

Both commits are pushed to `origin/alanvardy-var-1170-increase-width-on-outer-duo-screen`.
The `DELETEME` marker was removed in `39a72984` before phase work began.

## Automated Checks

Phase 1:
- [x] `make format` — no diff beyond the phase's files
- [x] `make lint` — `swiftformat --lint` + `swiftlint lint --strict`, 0 violations
- [x] `make build` — `** TEST BUILD SUCCEEDED **` (SIM pinned from `.simulator_id`)
- [x] `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` — ok: 9 cases
- [x] `scripts/test-one.sh SingleThreadTests/DuoDisplayTests` — ok: 6 cases
- [x] `scripts/test-one.sh SingleThreadTests/DuoOuterPortraitTests` — ok: 5 cases
- [x] `scripts/test-one.sh SingleThreadTests/CardWidthTests` — ok: 4 cases (default path untouched)
- [x] Grep guard: no remaining `padding(.horizontal, 40)` / `CardWidth.maxContentWidth` in `SingleThread/ContentView.swift`

Phase 2:
- [x] `make format` then `make lint` — 0 violations
- [x] `make build` — `** TEST BUILD SUCCEEDED **`
- [x] `scripts/test-one.sh SingleThreadTests/ChecklistLayoutTests` — ok: 10 cases (new real-viewport test added)
- [x] `scripts/test-one.sh SingleThreadTests/CardWidthTests` — ok: 4 cases
- [x] `make periphery` — Phase 2 criterion satisfied: no unused `EmptyStateCard.maxContentWidth` / new symbol. One pre-existing, unrelated `ReminderCardView.swift:74 'swipeOffset'` finding (Xcode 27 `$`-projection false positive; file untouched, byte-identical on `origin/main`) — CI (Xcode 26.6) is the authority
- [x] `rg -n "horizontal, 40|EmptyStateCard.maxContentWidth" SingleThread/` — returns nothing

Deviations (toolchain-forced, approved/adapted):
- SwiftLint `type_body_length`: `ContentView` was at 499 lines; Phase 1 additions pushed it over. A scoped `// swiftlint:disable:next type_body_length` with rationale was added above `struct ContentView` (supervisor-approved Option A).
- `@Environment` attributes split onto their own lines per SwiftLint `attributes`.
- `ChecklistLayout.Context.standard` marked `nonisolated` (MainActor default isolation).
- Force-unwrap in `DuoOuterPortrait.machineIdentifier` replaced with `guard let` per `force_unwrapping` ban.
- SwiftFormat cosmetic reordering (`layoutContext` internal section, `Context` static-before-stored, `Self(...)`).

## Manual Verification Items (from the plan)

- [ ] Boot this worktree's simulator (`simctl boot <UDID from .simulator_id>`), install and launch: the reminder card looks exactly as before — card width `min(340, viewportWidth * 0.6)`, 40 pt gutters, no layout shift
- [ ] Rotate to landscape: unchanged
- [ ] Preview (`#Preview`) of `ContentView` still renders the card correctly (the new environment values default to nil → `.standard`)
- [ ] Fill the list with no reminders (`.allDone`) and with hidden-only reminders (`.empty`): the empty-state card is unchanged on a non-Duo simulator
- [ ] Force the AI-sort failure banner (`appViewModel.retryAIRanking()` path or the existing UI-test seam): its 40 pt gutter is unchanged on a non-Duo simulator
- [ ] On a physical iPhone Duo (hardware-dependent — no Duo simulator exists): outer screen in **portrait** shows the card at `min(340, viewportWidth * 0.8)` with 20 pt gutters and the banner aligned to the card; the **inner** screen and **outer landscape** are unchanged at 40 pt / 0.6 cap. If hardware is unavailable, record that in the PR completion artifact and treat the unit tests as the authority
- [ ] Full CI-identical gate (`./scripts/test.sh` via the `run-gate` skill) runs ONCE after both phases are committed
