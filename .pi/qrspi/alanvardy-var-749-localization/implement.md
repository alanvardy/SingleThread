# Implementation Summary

Localization for all four targets (iOS/macOS app, watchOS app, widget, `SingleThreadCore`) through string catalogs and `InfoPlist.strings`, shipping English + zh-Hans, es, ja, de, fr — verified by en-locale-pinned unit tests, identifier-based UI tests, and the expanded `LocalizationTests` suite.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `9cc7f0d` | Phase 1: string catalog infrastructure |
| 2 | `353fe5f` | Phase 2: accessibility identifiers |
| — | `5099778` | fix: persist pin-wallpaper toggle via the settings write-back chain (interleaved dependency fix) |
| 3 | `e3c59b9` | Phase 3: core shared strings migration |
| 4 | `62411fc` | Phase 4: app target localization |
| 5 | `c82b0fe` | Phase 5: watch + widget localization |
| 6 | `770ab8d` | Phase 6: test migration & final verification |
| — | `4bd53c2` | docs: mark Phase 6 automated checks complete |

## Automated Checks

- [x] Phase 1: targeted `xcodebuild -only-testing:SingleThreadTests/LocalizationTests` passes; `make build` + `make watch-build` succeed (empty/wired catalogs wired via `Bundle.module` and per-target `InfoPlist.strings`)
- [x] Phase 2: `make ui-test`, `make watch-ui-test`, `make test` pass with zero changes to existing assertions (identifiers added only)
- [x] Phase 3: Core unit suites (`ReminderSkip`, `ReminderRecurrenceFormatter`, `AppInfo`, `ReminderIntents`) green under pinned en locale; `make build` + `make watch-build` prove `Bundle.module` resolves in app + watch processes
- [x] Phase 4: `make test`, `make ui-test`, `make build`, `make lint` pass under en locale
- [x] Phase 5: `make build`, `make watch-build`, `make watch-test`, `make watch-ui-test` pass
- [x] Phase 6: `make format`, `make lint` (`swiftformat --lint` + `swiftlint lint --strict`) clean
- [x] Phase 6: `make test` — all iOS unit suites green under pinned `en`
- [x] Phase 6: `make ui-test` — all 8 iOS UI files green on accessibility identifiers
- [x] Phase 6: `make watch-ui-test` — both watch UI files green
- [x] Phase 6: `make periphery` — zero dead code
- [x] Phase 6: `./scripts/test.sh` — full CI-identical gate passes (format, lint, build, watch build, Periphery, unit + UI + watch UI, macOS build + unit tests)

## Manual Verification Items (from the plan)

- [ ] **Phase 1**: Open the project in Xcode: each target's `Resources/Localizable.xcstrings` opens in the string-catalog editor with en + 5 languages; `InfoPlist.strings` appear as localizations (not plain groups) after the `knownRegions` edit.
- [ ] **Phase 1**: Confirm the generated app/watch `Info.plist` in `DerivedData/…/SingleThread.app/Info.plist` still contains the English usage strings (build-setting fallback), and the app bundle contains `zh-Hans.lproj/InfoPlist.strings` etc.
- [ ] **Phase 2**: In the iOS simulator (`make simverify`), run the app with VoiceOver: every button/row still reads its English a11y label; no element lost its label to the identifier.
- [ ] **Phase 3**: Temporarily run one Core test with a `Locale(identifier: "zh-Hans")` override and confirm `displayName`/recurrence output changes (then revert) — sanity-checks that the catalog, not the fallback, is serving.
- [ ] **Phase 4**: Launch the app in the simulator and click through Settings → every sub-screen, the About screen, the swipe prompt, the dictation error path, and the upgrade prompt — all still read natural English (no raw keys, no missing strings).
- [ ] **Phase 5**: Add the widget to the simulator home screen: gallery name/description, empty state, and a seeded reminder render correctly.
- [ ] **Phase 5**: Launch the watch app in the watch simulator: empty states, action buttons, confirmation dialog, and upgrade prompt render without raw keys.
- [ ] **Phase 6**: Set the simulator language to `Deutsch` (Settings → General → Language & Region → German), relaunch, and spot-check: settings rows, empty state, action buttons, About, and the widget all render German; usage-description strings appear in German when triggering Reminders/mic permission.
- [ ] **Phase 6**: Repeat for `zh-Hans` and `es` (quick spot-check; the full six languages are validated structurally by `LocalizationTests`).
- [ ] **Phase 6**: Review the machine-translated strings for gesture metaphors (`Swipe left/right`) and plural forms; correct any that are culturally wrong in the catalogs.
- [ ] **Phase 6**: Create the App Store listing localization follow-up ticket in Linear (VAR-xxx) — out of scope for this change but documented in the design.

## Notes / Deviations Encountered During Implementation

- **Phase 3 intent-title adaptation (pre-existing)**: `CompleteReminderIntent`/`SkipReminderIntent` titles are declared as `LocalizedStringResource` literals resolving against the widget/app catalog (keys live in the widget + app catalogs, not Core's) — the plan's Core-catalog version was adapted in the earlier Phase 3 run; verified working.
- **en-locale pinning**: `String.en(_:bundle:table:)` helper added in `SingleThreadTests/LocalizationTestHelpers.swift`. Core-bundle lookups use `Bundle.core` (runtime resolution of `SingleThreadCore_SingleThreadCore.bundle` from `Bundle.main`) because the Xcode test bundle cannot access the package-only `Bundle.module`; app lookups use `Bundle.main`.
- **Phase 6 UI tests**: 2 of the 8 iOS UI files (`ActionButtonsUITests`, `SingleThreadUITestsFlows`) and their identifier migration predated this run (committed with the plan); the remaining 6 iOS + 2 watch files were migrated here. All green.
- **watchOS dialog buttons**: `confirmationDialog` actions expose their **label**, not the SwiftUI identifier, on watchOS — the dialog `Refresh`/`Delete` lookups keep label matching (`"Refresh"`, `"Delete"`) while all other watch lookups use identifiers (`completeButton`, `skipButton`, `emptyStateTitle`, `priorityMarker`, `upgradePrompt`, `refreshButton`-outside-dialog). Documented inline in the tests.
- **Periphery**: `SharedStrings.deleteReminderAccessibility` was only referenced inside the macOS `#if` branch, which the iOS-destination Periphery scan doesn't compile — fixed by using the shared a11y label on the iOS delete context-menu button too (consistent with the shared-key intent).
- **Orphaned-key scan**: run as a grep script over each catalog against its target sources; **zero genuinely orphaned keys**. The scan's initial flags were false positives: the four privacy-guide bodies are multi-line concatenated literals in `PrivacySettingsContent.swift`, and the widget `Complete Reminder`/`Skip Reminder` keys are the AppIntent titles declared in Core.
- **Local environment**: unit tests that complete reminders via default stores failed locally until the App Group `completionCount` (at the 100-cap from prior app/UI-test runs) was reset — `ReminderStore.canMutate` gates completion at `count < 100`. CI runners are fresh and unaffected. Not a code defect; no repo change made.
- **Full-gate run**: the first complete `./scripts/test.sh` run was killed (SIGKILL) during the final macOS unit-test step's result finalization on this 24 GB / 98%-full machine; a standalone rerun of that step passed 427/427 (exit 0 with `-quiet` + result bundle in /tmp), and the subsequent full gate run passed end-to-end (`✅ All CI checks passed.`).