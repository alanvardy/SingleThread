# Done

- **Branch / head SHA**: `alanvardy-var-1181-sentry-error-nsinvalidargumentexception` @ `494d0aa6783b9d2ba828bf7489aa6705fb96aff9`

## Mechanical checks

- `make format` — clean (261 files, SwiftFormat reports no changes).
- `make lint` / `swiftlint lint --strict` — 0 violations, 0 serious (248 files).
- **Full CI-identical gate (`./scripts/test.sh`) — ✅ PASS** on `494d0aa6`, every stage:
  1. Deployment-target / package-floor verify ✓
  2. Every-xcodebuild-wrapped verify ✓
  3. Format + SwiftFormat `--lint` ✓
  4. SwiftLint `--strict` ✓
  5. Warning-check self-test (20 fixtures) ✓
  6. iOS build (`** TEST BUILD SUCCEEDED **`, no un-allowlisted warnings) ✓
  7. Watch build ✓
  8. **Periphery (stage-fatal) — passed, "No unused code detected."** ✓
  9. iOS UI tests — 7 cases ✓
  10. Watch UI tests — 1 case ✓
  11. Watch unit tests — 81 cases ✓
  12. macOS unit tests (`SingleThreadTests`) — 868 cases, `** TEST SUCCEEDED **` ✓
  - Gate log: `/tmp/gate-var-1181e.log` (`✅ All CI checks passed.`).

## Review outcome

One bounded fresh-context reviewer covered correctness/soundness, test validity, the
test-infrastructure change, Swift hazards, and conventions. On-disk diff inspected
independently by the parent. Outcomes:

- **Blocker fixed (B1, reviewer P0)** — `SingleThreadTests/ReminderIntentSupportTests.swift`:
  `completeOutcomeNamesTheCompletedTask` and `completeOutcomePersistsThroughInMemoryEventStore`
  seeded nil-calendar reminders and asserted a successful completion; the new `isSavable`
  guard made them fail. Fixed to `makeSavedReminder(title:)` (`d3d8c056`), plus
  `completeOutcomeReportsFailureWhenSaveThrows` so it still exercises the throwing-`save` path.
- **Second blocker found by the gate, fixed** — `SingleThreadTests/ReminderDictationTests.swift`
  (`startDictationAddsReminderAndFlowsText`) was another missed `addReminder` caller (asserted
  persistence with a nil-calendar store). Fixed (`494d0aa6`).
- **Pre-existing main CI breakage fixed while unblocking the gate** — `SingleThreadUITests/SingleThreadUITests.swift`
  `containsSaturatedGreen` read the `@MainActor` `XCUIScreenshot.image` from a nonisolated
  context. This warning was byte-identical to `origin/main` and main's own CI was red on it
  (`ui-tests-smoke`/`unit-tests` Build); introduced by `25913f57` (prior ticket). Fixed with
  `@MainActor` (`8ba5c9d4`). Not part of VAR-1181's behavioral change; flagged here explicitly.
- **Reviewer P1 rejected** — the claim that the new `calendar != nil` clause is not
  independently red-first was **disproven** by an empirical EventKit run: an unsaved
  `EKReminder(eventStore:)` has a **non-empty** `calendarItemIdentifier` and nil `calendar`,
  so the sad-path tests using `makeReminder(title:)` trip only the new clause (the old
  empty-identifier guard would have let them reach `save`).
- **Accepted as-is** — `completeReminderSkipsSaveWhenIdentifierIsEmpty` passes for the wrong
  reason; pre-existing, explicitly out of scope in `plan.md`. `deleteReminder` (`remove`) is
  intentionally unguarded. `InMemoryEventStore.sharedStore` unification and the file-scope
  `isSavable` were reviewed and found sound.
- **Flake triaged, not a regression** — an intermediate gate run failed only on
  `CompletionMomentumOverlayTests/retriggerResetsTimer()` under heavy concurrent load
  (another session's tests); the test is byte-identical to main, untouched by this branch,
  and passed 3/3 in isolation. The clean re-run on an idle machine passed.

No optional improvements were declined; the review's fix list was exhausted.

## Remaining manual items

- **On-device confirmation of the Sentry fix** — the crash (`SINGLETHREAD-3`:
  `NSInvalidArgumentException` from `EKEventStore.save`) is only provably gone when the
  app runs against a real EventKit store; the unit tests prove `save` is now unreachable
  for a key-less reminder. Watch Sentry after release for a recurrence.
- **Plan's red-first manual check** — not performed as an actual pre-guard revert; the
  premise is established by the verified fixture semantics (unsaved reminder = non-empty id
  + nil calendar) plus the gate's green/red history. The `saveCallCount == 0` assertions are
  the proof points.
- **`--ui-testing` fixture note** — a plain `--ui-testing` seeded reminder (no calendar) now
  no-ops on Complete instead of crashing; no UI test taps Complete under plain `--ui-testing`,
  so no UI test changed. A live-QA completion of that fixture will no-op rather than crash.
