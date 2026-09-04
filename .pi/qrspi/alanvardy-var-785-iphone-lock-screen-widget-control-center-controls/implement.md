# Implementation Summary

All 3 phases implemented, verified, and committed.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | d8cb8ed | Core NextThingSummary presentation/status type |
| 2     | c2f28f9 | Lock Screen accessory families |
| 3     | 380bd47 | Control Center Complete + Skip controls |

## Automated Checks

- [x] Phase 1 targeted: `NextThingSummaryTests` (10 tests) pass on iPhone 17 simulator
- [x] Phase 1: full `make test` (`./scripts/test.sh --unit-only`) green
- [x] Phase 2: `make build` compiles `SingleThreadWidget.appex` with the family switch + 3 accessory views
- [x] Phase 2: `make lint` clean
- [x] Phase 2: full unit suite green (no regression)
- [x] Phase 3: `make build` compiles the mixed Widget + ControlWidget bundle body (the cross-cutting seam)
- [x] Phase 3: `make lint` clean
- [x] Phase 3: `make test` — `ReminderIntentsTests.completeIntentIsConfigured` / `skipIntentIsConfigured` green
- [x] Full `./scripts/test.sh` (format, lint, iOS+watch build, Periphery, unit + UI + watch + macOS tests) — **all CI checks passed**

## Manual Verification Items (from the plan)

- [ ] Open the Lock Screen gallery (long-press Lock Screen → Customize → Add Widget → SingleThread): the three accessory variants appear and each renders the next-reminder summary.
- [ ] For the `.allDone` / `.empty` / `.noAccess` positions, the accessory variants render the minimal glyph+word (checkmark "done", checklist, lock).
- [ ] On a device (gallery surfacing is not reliable in the simulator): Control Center → Customize Controls (plus button) → SingleThread shows **Complete** and **Skip**.
- [ ] Tap **Complete** — the first visible reminder completes through `completeCurrentReminder()` (freemium cap 100, counter incremented).
- [ ] Tap **Skip** — the first visible reminder skips via the synchronous immediate write (`skipCurrentReminderImmediately()`), same path as the widget's existing Skip button.

## Deviations / Observations from the plan

1. **`@ViewBuilder` added to `mainView`** (`NextThingWidget.swift`). The plan said "move the current `body` switch unchanged," but SwiftUI only applies implicit ViewBuilder type-unification to the `body` accessor. The identical `switch` fails to compile inside a named computed property with heterogeneous `some View` branches. Added `@ViewBuilder` — the exact idiom already used at `SingleThread/ContentView.swift:337` (`@ViewBuilder private var authGatedContent`). Home-screen rendering is otherwise byte-identical to before.

2. **`accessibilityLabel` added to `accessoryCircularView`'s `Image`**. SwiftLint's `accessibility_label_for_image` (opt-in, --strict) requires a context-bearing `Image` to have a label or be hidden. The circular accessory's glyph is the entire status display, so I labelled it with `summary.rectangularTitle` rather than hiding it.

3. **Test variable renames** in `NextThingSummaryTests.swift` (`on`→`onSummary`, `off`→`offSummary`). The plan's test used `on`/`off`, which violate SwiftLint `identifier_name` (≥3 chars). Semantic behavior unchanged.

4. **Process deviation**: The intended subagent-per-phase delegation could not be used — the pi subagent runner itself crashed at boot on every launch (`Cannot find module …/pi-agent-core/dist/index.js/node` — a version mismatch in the installed pi tooling). I implemented, verified, and committed each phase directly in the main agent instead, preserving the one-commit-per-phase and read-before-write discipline. This is an infrastructure issue unrelated to the repo; the final `./scripts/test.sh` gate passed, which is the source of truth.

5. **Plan checkboxes**: All automated items across Phases 1–3 are marked `[x]`. Manual items (above) left `[ ]` for user confirmation.

## Notes for follow-up (no action taken — out of scope)

- None of the surrounding code required change beyond the plan. No new localized strings were introduced (`LocalizationTests` untouched).