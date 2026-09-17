# Phase 4 Report — Reminder + main-screen surfaces localized

**Commit**: `311e2818` — "Phase 4: reminder and main-screen surfaces localized"
**Branch**: `alanvardy-var-1034-set-language` (pushed, non-fast-forward clean)

## What was implemented (plan.md lines 866–972)

### 1. App catalog keys (`SingleThread/Resources/Localizable.xcstrings`)
Checked every plan-listed literal against the exact catalog key; only two were genuinely
missing, both added with all six languages (non-English values differ from English):

- `You've cleared %lld today` — ContentView.swift:592 completion-momentum overlay. Added
  with `variations.plural` (one/other for en/es/de/fr, other-only for zh-Hans/ja) matching the
  sibling key `You have %lld reminders waiting — open SingleThread!`.
- `Completion Momentum` — ReminderSettingsView.swift:98 toggle label.

Verified already-present (no-op): ContentView:390, ReminderCardView:189/196/206,
FilterSortSettingsView:27/34/49, InterfaceSettingsView:44/56/65/80/91/103/116/128,
ReminderSettingsView:28/44/55/71, NotificationsSettingsView:16/25-27/30,
BackgroundSettingsView:23/33/37/46, RescheduleSheet:25, ExcludedListsView:27.
No endonym catalog entries added. JSON validated: 141 keys, parses cleanly.

### 2. Eager `String(localized:)` sites → resources
- `ContentView.swift` 218 (macOS refresh a11y value), 733 (`Processing` a11y label),
  758 (`Open Settings` Button) → `LocalizedStringResource(..., table:, bundle:)` handed to the view.
- `ReminderDictation.swift` 227, 239 (`errorDescription`) → `.resolvedInAppLanguage()`.
- `ReminderCardView.swift` 128 (`Has alarm` a11y label) → resource handed to view;
  also converted the nudge-banner a11y `String(format:)` site (Skipped %lld times) to resolve
  the format against the app language.
- `CreationFeedback.swift` 29-30 (`accessibilityLabel`) → `.resolvedInAppLanguage()`; added
  `import SingleThreadCore`.
- `ContentViewModel.swift` 105 — no change needed: already a `LocalizedStringResource`
  (Phase 2 deviation 2).

### 3. Non-View / scheduler sites
- `NotificationScheduler.swift` 82/84 → `LocalizedStringResource(...).resolvedInAppLanguage()`
  (keys confirmed in the App `.main` catalog; existing bundle kept).
- `ReminderSkip.swift` / `ReminderRecurrenceFormatter.swift` — verified: no eager
  `String(localized:)` remains (Phase 2 already converted).

### 4. `SortOption.title` → `LocalizedStringResource`
- `SortOption+Presentation.swift`: `title` now returns `LocalizedStringResource`
  (`Priority`/`Due Date`/`Title` — keys already present).
- `FilterSortSettingsView.swift` `Label(option.title, ...)` needed no change
  (Label accepts `LocalizedStringResource`, same as the Appearance/TextSize pickers).
- `SortOptionTests.swift`: `presentationTitlesAreHumanReadable` now resolves with
  `.resolved(in: Locale(identifier: "en"))`.

### Tests
- `LocalizationTests.swift`: **no structural change** (catalog-wide invariant covers the
  two new keys — confirmed by the run).
- `SingleThreadTests.swift`: added `rescheduleStringResolvesInGerman` asserting
  `LocalizedStringResource("Reschedule", table: "Localizable", bundle: .main)
  .resolved(in: Locale(identifier: "de")) == "Neu planen"` (catalog de value, differs from English).
- `SortOptionTests.swift`: updated as above.

## Verification results (automated)

| Check | Result |
|---|---|
| `scripts/test-one.sh SingleThreadTests/LocalizationTests` | green — 5 case(s) ran |
| `scripts/test-one.sh SingleThreadTests/SingleThreadTests` | green — 9 case(s) ran |
| `scripts/test-one.sh SingleThreadTests/SortOptionTests` | green — 5 case(s) ran |
| `make format && make lint` | clean — 0 violations, 0 serious (193 files) |
| `rg -n 'String\(localized:' SingleThread SingleThreadCore` | only Phase 5 sites + helper remain (see below) |

The full `./scripts/test.sh` gate was **not** run (per-phase policy; runs once after Phase 6).

## Residual `String(localized:)` list (exact)

```
SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:111   (helper: `resolved(in:)` body — must stay)
SingleThread/MenuBarExtraOptions.swift:34                                    (Phase 5 scope — menu bar locale)
SingleThread/BackgroundSettingsView.swift:70                                 (Phase 5 scope — Refreshing a11y value)
SingleThread/SingleThreadApp+Commands.swift:17                               (Phase 5 scope — About SingleThread)
SingleThread/SingleThreadApp+Commands.swift:23                               (Phase 5 scope — Quit SingleThread)
```

The "debug-only exceptions" listed in the task (ContentView+iOS.swift:26,28; ContentView.swift:
331,701,711,721) are `Text(...)` literals, not `String(localized:)` calls, so they never appear
in this grep — consistent with plan.md line 963 ("only Phase 5 sites and the debug-only
exceptions remain"). Helper line 111 is the `resolved(in:)` implementation itself and cannot be
converted.

## plan.md
Phase 4 automated checkboxes (lines 959–963) flipped to `[x]`; Manual items (967+) and prior
phases untouched.

## Observations / adaptations
- Converted the two additional `errorDescription` cases in `ReminderDictation.swift`
  (`recognizerUnavailable`, `microphoneDenied`) and the `Skipped %lld times — tap to manage`
  a11y label in `ReminderCardView.swift` — same eager `String(localized:)`-to-resource
  conversion, same files, and required for the "no leftover English" outcome. All keys exist
  in the catalog.
- `First run hit an environmental BUILD INTERRUPTED / 1500 s timeout once; resolved by
  shutting down the worktree sim and re-running (two consecutive green runs for
  LocalizationTests).`
- No catalog keys were added for the line-99 ReminderSettingsView caption
  (`Show "You've cleared N today"...`) — it is not in the Phase 4 checklist and is a Phase 5
  "remaining literals" item.