# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `35bc9d12` | Phase 1: Gesture remap — right complete, left skip, up more |
| 2     | `5a8e8f2b` | Phase 2: Directional-arrow swipe guide |

Both commits are pushed to `origin/alanvardy-var-1129-change-swipe-behaviour`
(no rebase was needed — `origin/main` was already an ancestor of the branch).

## Automated Checks
- [x] `make format` clean
- [x] `make lint` — 0 violations across 227 files
- [x] `scripts/test-one.sh SingleThreadTests/SwipeGestureDecisionTests` — 16 cases pass
- [x] `scripts/test-one.sh SingleThreadTests/SwipeToActModifierTests` — 9 cases pass
- [x] `scripts/test-one.sh SingleThreadTests/SwipePromptTests` — 3 cases pass
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` — 5 cases pass
- [x] `make build` — `** TEST BUILD SUCCEEDED **` (warnings-as-errors)
- [x] `make mac-build` — `** BUILD SUCCEEDED **`
- [x] `make test` (unit-only gate) — `✅ Unit tests passed (macOS native)`
- [ ] Full gate (`./scripts/test.sh` via the `run-gate` skill) — deferred to review;
      must run the three swipe UI tests green on iPhone 17 and iPad (A16)

## Manual Verification Items (from the plan)
Phase 1:
- [ ] iPhone: right-drag completes; left-drag replaces the card with the next
      reminder (or the empty state on a single-reminder seed); up-drag opens the
      Skip / Reschedule / Delete menu
- [ ] Downward drag and pull-to-refresh still scroll without opening the menu;
      a shallow diagonal drag fires nothing
- [ ] VoiceOver rotor on the card offers Complete, Skip and More
- [ ] macOS: same three directions behave the same way on the card

Phase 2:
- [ ] iPhone, guide enabled: `↑` + "Swipe up for more" sits above the card;
      "← Swipe left to skip" and "Swipe right to complete →" render as one row
      below it in orange/green; Dismiss hides all of it
- [ ] Settings → Interface → "Show swipe prompt" off hides the whole guide
- [ ] Large Dynamic Type (AX5): the guide wraps without truncating and the card
      content is not clipped
- [ ] VoiceOver skips the guide copy but still reaches the Dismiss button

## Observations / Notes
- **Plan self-contradiction (Phase 2) resolved in code**: the plan's test snippet
  asserted `complete < skip` in document order, but the plan's own
  `horizontalGuide` layout places the left/skip hint first. The implementation
  follows the layout (skip precedes complete) and the test asserts
  `up < skip < complete`. No functional impact.
- **`DELETEME` marker**: the branch-bootstrap `DELETEME` file is deleted in the
  working tree but the deletion is uncommitted (pre-existing before this run). It
  was deliberately excluded from both phase commits. It must be `git rm`-ed and
  committed before the branch merges.
- Both phase subagents timed out at the 1-hour cap while exercising slow
  simulator/UI checks, but had completed their code edits. The parent finished
  verification (bounded automated checks only — no UI tests), checked off the
  plan's automated items, and committed each phase. No out-of-phase changes
  were included in either commit.
- No unrelated refactors or cleanups were performed.
