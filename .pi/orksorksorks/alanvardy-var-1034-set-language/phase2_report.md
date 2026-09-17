# Phase 2 Report — Shared strings become deferred resources

Branch: alanvardy-var-1034-set-language · Commit: `f346a1015339f190f55d0bc5da93cb6f1dbcb085`
("Phase 2: shared strings become deferred localized resources")

## Scope implemented

Every `SharedStrings.*` accessor, the recurrence summary, the priority display
name, the settings-link-label title, and the empty-state copy are now
`LocalizedStringResource`s; app, watch, and widget render them in the chosen
language via `\.locale` (Views) or `resolved(in:)` / `resolvedInAppLanguage()`
(non-View).

### Core (SingleThreadCore)
- `LocalizedString+Shared.swift` — all 19 `public static var <member>`s +
  `priorityAccessibilityLabel` now use `LocalizedStringResource` with identical
  key/table/bundle. Doc comments and `// periphery:ignore` markers preserved.
- `ReminderRecurrenceFormatter.swift` — `format(_:) -> LocalizedStringResource?`;
  all 8 branches return resources (Daily/Weekly/Monthly/Yearly + four
  "Every N …" plural keys).
- `ReminderDisplay.swift` — `recurrenceSummary: LocalizedStringResource?`
  (field + convenience-init default).
- `ReminderSkip.swift` — `ReminderPriority.Level.displayName` is
  `LocalizedStringResource`.

### App
- `ContentViewModel.swift` — `EmptyStateCopy.title/description` are resources;
  `emptyStateCopy(hasHidden:)` / `allDoneStateCopy()` build resources
  (`bundle: .main`), incl. the dynamic `String.LocalizationValue` descriptions.
- `SettingsCaption.swift` — `SettingsLinkLabel.title: LocalizedStringResource`.
- `SettingsView.swift` — `LocalizedStringKey(SharedStrings.reminder)` →
  `SharedStrings.reminder`; the `purchaseTitle` local retyped to
  `LocalizedStringResource` so the literal ternary converts (the compiler
  rejected the `LocalizedStringKey` value — the one consumer-shape mismatch
  found; fixed minimally per the plan's String-typed-parameter rule).
- `EmptyStateCard.swift` — no change needed (`Text(copy.title|description)`
  already accept resources).

### Widget
- `NextThingWidget.swift` — `messageView(title: LocalizedStringResource,
  systemImage: String, message: LocalizedStringResource?)` (String-typed params
  per plan's table); the `.noAccess` `String(localized:)` message became
  `LocalizedStringResource(...)`.

### Watch
- No source changes required — every consumer (`Label`/`Text`/`ProgressView`/
  `Button`/`.accessibilityLabel`/`.confirmationDialog`) already accepts the
  resource; watch build proves it.

### Tests
- `ReminderRecurrenceFormatterTests` — `formatted(frequency:interval:)` helper
  resolves the resource in `Locale(identifier: "en")`; added `import Foundation`.
- `ReminderDisplayTests` — `recurrenceSummary` resolved before comparing.
- `SingleThreadTests` — `.title`/`.description` (+ the distinct-title `!=`
  check) resolved in en.
- `ReminderSkipTests` — `displayName` assertions resolved; added
  `import Foundation`.
- `AppLanguageTests` — added `sharedStringResolvesToEveryShippedLanguage`
  (en "Skip", zh-Hans "跳过", es "Omitir", ja "スキップ", de "Überspringen",
  fr "Passer").
- `ShowRecurrenceTests` — compiled unchanged (string literal → resource via
  `ExpressibleByStringLiteral`).
- `LocalizationTests` — untouched, green (safety net).

## Verification (all ran, final formatted state)

| Command | Result |
|---|---|
| `scripts/test-one.sh SingleThreadTests/LocalizationTests` | ok: 5 cases |
| `scripts/test-one.sh SingleThreadTests/AppLanguageTests` | ok: 7 cases (> 6, includes new test) |
| `scripts/test-one.sh SingleThreadTests/ReminderRecurrenceFormatterTests` | ok: 2 cases |
| `scripts/test-one.sh SingleThreadTests/ReminderDisplayTests` | ok: 9 cases |
| `scripts/test-one.sh SingleThreadTests/ShowRecurrenceTests` | ok: 1 case |
| `scripts/test-one.sh SingleThreadTests/SingleThreadTests` | ok: 8 cases |
| `scripts/test-one.sh SingleThreadTests/ReminderPriorityTests` | ok: 3 cases |
| `scripts/test-one.sh SingleThreadTests/ReminderSkipLogicTests` | ok: 2 cases |
| `scripts/test-one.sh SingleThreadTests/ReminderNotesFormatterTests` | ok: 2 cases |
| `scripts/test-one.sh SingleThreadTests/ReminderSortTests` | ok: 11 cases |
| `make watch-build` | ** BUILD SUCCEEDED ** |
| `make build` (pinned `.simulator_id`) | ** TEST BUILD SUCCEEDED ** |
| `make format && make lint` | done; 0 violations, 0 serious |

Note: the plan's `ReminderSkipTests` suite name matched zero cases (the file
contains four structs); the run was split into the four actual suites —
`ReminderPriorityTests` (displayName) and `ReminderSkipLogicTests` plus the
two untouched ones (`ReminderNotesFormatterTests`, `ReminderSortTests`) — all
green. Zero-match would have been a silent pass, so the actual+sibling suites
were run to prove execution.

## plan.md

Phase 2 automated checkboxes (lines 634–645) flipped `- [ ]` → `- [x]`.
Manual items, Phase 1 items, and the Testing-checkpoint table untouched.

## Observations / adaptations

1. `purchaseTitle` (`LocalizedStringKey` var) was the one consumer-shape the
   plan's table didn't pre-specify: `title: LocalizedStringResource` cannot
   take a `LocalizedStringKey` *value* (only literals convert). Minimal fix:
   `let purchaseTitle: LocalizedStringResource = ... ternary of literals`.
2. `ReminderSkipTests` is a multi-struct file — `-only-testing:` needs the
   struct names.
3. The widget's `messageView` took `String`-typed `title`/`message`; both
   params changed to resource types (plan's String-param rule) — non-View
   eager `.resolvedInAppLanguage()` was not appropriate inside a View.
4. `LocalizedStringResource("Every \(interval) days", …)` keys stay verbatim
   (matching today's `String(localized:)` keys); the catalog's plural keys
   (`Every %lld days`) are a Phase 4 content-sweep concern, not this phase.
5. No `String(localized:)`/`LocalizedStringKey(` site remains inside a
   SharedStrings accessor; remaining eager sites are Phase 4/5 content.

## Residual risks

- `make build`/`watch-build` compile the app/watch/widget targets but are not
  the full CI gate (`./scripts/test.sh` runs once after Phase 6 via run-gate).
- The `%lld` plural-key/`Every N`-key divergence noted above is pre-existing
  and unfixed by design (Phase 4 scope).
- `SharedStrings.priorityAccessibilityLabel` call sites were compile-verified
  through the app/watch builds (not exercised at runtime by unit tests).
- macOS-only paths (e.g. `MenuBarExtraOptions`, command menus) compile under
  `make build` (iOS) but not under a macOS-target build this phase — their
  resource usage matches the compile-verified forms.