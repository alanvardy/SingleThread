# Implementation Summary

Root cause, fix scope, and verification for VAR-1112 ("make links in reminder titles and notes tappable").

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `be78fc16` | CodeSpanFormatter segmenter (pure refactor) |
| 2     | `8fc6beb6` | LinkFormatter detection + attributed string |
| 3     | `1c3b75e0` | Wire links into the app end-to-end |
| 4     | `fdcd6567` | Accessibility custom actions + localization |
| 5     | `a2b3bfc8` | Best-effort UI test + manual verification doc |

All 5 phases landed on `alanvardy-var-1112-make-links-in-reminder-titles-and-notes-tappable` and were pushed to origin.

## Automated Checks

- [x] `make format` then `make lint` pass (all phases, 0 violations)
- [x] `scripts/test-one.sh SingleThreadTests/CodeSpanFormatterTests` passes (11 cases)
- [x] `SIM=<pinned> scripts/test-one.sh SingleThreadTests` compiles the package
- [x] `scripts/test-one.sh SingleThreadTests/LinkFormatterTests` passes (10 → 11 cases after Phase 4's order test)
- [x] `scripts/test-one.sh SingleThreadTests/ReminderDisplayTests` passes (12 cases)
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes (5 cases)
- [x] `make build` succeeds (card/row/scene compile, no source-located warnings)
- [x] `scripts/check-appgroup-notify.sh` passes
- [x] New localization key `"Open link to %@"` is present in all six languages and every non-English value differs from English
- [x] Final scope checks: widget/watch (`NextThingWidget`, `WatchReminderView`) still use `titleAttributed`/`notesAttributed`; no link affordance added there; card/row use the `…WithLinks` accessors
- [x] Phase 5 UI-test fallback rule applied and documented (see below)

## Manual Verification Items (from the plan)

- [ ] Confirm no existing `CodeSpanFormatterTests` assertion text changed in the diff (pure refactor)
- [ ] Spot-check `links(in:)` against the ticket's rule list (localhost/IP hosts with a scheme match; bare domains do not)
- [ ] Launch the app against a seeded reminder with a URL in its title; tap the link and confirm the browser opens
- [ ] Confirm the widget and watch render URLs as plain text (no link affordance)
- [ ] With VoiceOver, focus the card; the rotor lists one "Open link to <host>" action per link and invoking it opens the URL
- [ ] Switch the app language to each of de/es/fr/ja/zh-Hans and confirm the action label changes
- [ ] The six manual steps in `docs/SimulatorManualVerification.md` (Tappable links/VAR-1112 section) pass on the pinned iOS simulator
- [ ] `docs/SimulatorManualVerification.md` renders the new section with correct code spans
- [ ] Full gate `./scripts/test.sh` green (run once via `run-gate` — depends on two final-check items below)
- [ ] PR notes the UI-test path taken (kept or dropped) and why

## Notes / deviations from the plan

1. **Phase 4 API adaptation.** The plan specified `.accessibilityCustomActions { AccessibilityAction(...) }`. That API does not exist in this SDK (iOS 17+/macOS 14+): `AccessibilityAction` is not in scope and there is no `accessibilityCustomActions` member. The correct modern API is `.accessibilityActions { Button { ... } label: { Text(...) } }`, which I verified compiles against the iOS 17 simulator SDK and the app target. The localized action label (`SharedStrings.openLink(to:)`) is unchanged.

2. **Phase 5 UI test dropped (fallback path).** The plan flagged the inline-tap XCUITest as best-effort with an explicit fallback rule: run it twice; if the coordinate tap misses or the spy label is wrong/flaky, delete the test method and the `.task` poll seam and document the unit-tests-plus-manual path. The test failed with `XCTAssertTrue failed - Spy overlay should surface after a link tap` (coordinate tap inside the title region did not get routed to the resolver), after also hitting two `RequestDenied` simulator-launch infra failures. I applied the fallback: removed `testLinkTapRoutesThroughURLOpenerSpy` and the ContentView `.task` poll seam (ContentView returned to its pre-Phase-5 state, no net change), keeping the manual-verification doc section. Detection and attribute construction remain covered by unit tests in Phases 2–4; only the SwiftUI `environment` routing step is verified manually.

3. **Delegation note.** Phases 2–5 were implemented by `worker` subagents, but their verification/commit was completed in the foreground by the parent because the `worker` runs repeatedly stalled on the shared simulator/`xcodebuild` slot (one `xcodebuild test` process at a time, contended with the `var-1105` ticket) and burned their 30-minute deadlines with complete-but-uncommitted trees. The phase implementations supplied by the workers were intact and reused; the parent ran the bounded verification, fixed a Phase 4 lint/API issue and the Phase 5 fallback, and committed. One known pre-existing flake remained in `AISortFailureBannerTests` during the Phase 3/4 full-`SingleThreadTests` compiles (timing-sensitive, touched only by an earlier VAR-1049 commit, unrelated to these changes).

4. **DELETEME marker removed** (housekeeping, per AGENTS.md) in an early commit `ca1ff69c`; it was required before rebasing and before the branch merges.

## Pending for review

- Full gate `./scripts/test.sh` (run once via `run-gate`, after phases committed).
- PR description should note the Phase 5 UI-test path taken and why (per final-check item).