# Phase 5 Report — Settings, purchase, and about surfaces localized + macOS menu-bar/commands locale

**Commit**: `d1c8aaac` — "Phase 5: settings, purchase, and about surfaces localized"
**Branch**: `alanvardy-var-1034-set-language` (pushed, fast-forward clean `311e2818..d1c8aaac`)

## Working tree start state
`git status --short` showed only untracked `.pi/orksorksorks/*.md` artifacts — no tracked
modifications (confirmed before any edit). No `DELETEME` deletion present in this checkout
(git status showed none); DELETEME untouched.

## What was implemented (plan.md lines 973–1051)

### 1. App catalog keys (`SingleThread/Resources/Localizable.xcstrings`, 141 → 144 keys)
Checked every plan-listed literal against the exact catalog key first (`rg '"<literal>"'`).
Genuinely **missing** (added with all six languages `en, zh-Hans, es, ja, de, fr`, each
non-English value differing from English to satisfy the `guardedCatalogs` identity guard):

- `Made with ❤️ by a Canadian developer 🇨🇦` — AboutView.swift:28 (`Text` literal).
  Translations: zh 由一位加拿大开发者倾心打造 ❤️ 🇨🇦 / es Hecho con ❤️ por un desarrollador
  canadiense 🇨🇦 / ja カナダの開発者が ❤️ を込めて作っています 🇨🇦 / de Mit ❤️ gemacht von einem
  kanadischen Entwickler 🇨🇦 / fr Fait avec ❤️ par un développeur canadien 🇨🇦.
- `Show "You've cleared N today" after completing a reminder.` — ReminderSettingsView.swift:99
  caption (the Phase 4→5 "remaining literals" item).
- `Purchase` — added per the task's explicit instruction (design session noted it missing;
  see Observations/adaptations — it has **no source literal consumer** in the current code).

**Verified already-present (no catalog work needed)**: all PurchaseSettingsView literals
(plan lines 27/30/32/35/45/51/128 → `You're all set! 🎉` … `Loading…`, `Unlock`, `Try Again`,
`Done`, `Product not available.`), AboutView `About` + `Copyright 2026 Alan Vardy`,
RescheduleSheet/ExcludedListsView leftovers, and every InterfaceSettingsView /
NotificationsSettingsView / ReminderSettingsView / BackgroundSettingsView literal
(ReminderSettingsView `Show "You've cleared N today"…` was the only gap).
`SingleThreadApp+Commands.swift:46-48` appearance tags — the keys `System`/`Light`/`Dark`
exist in the catalog (used via `AppearanceMode.title`); **verified but reported**: the macOS
**Commands** Appearance picker uses plain string literals (`Text("System")`, `Picker("Appearance")`),
not key references, so that submenu still renders English (see Residual issues).
JSON validated after edit: parses cleanly; the 3 new keys carry non-empty values in all six
languages, non-English differing from English.

### 2. Eager `String(localized:)` sites → `.resolvedInAppLanguage()` (non-View sites)
- `MenuBarExtraOptions.swift:34` (`Open SingleThread` Button) → `Button(LocalizedStringResource(…).resolvedInAppLanguage())`.
- `BackgroundSettingsView.swift:70` (`Refreshing` a11y value) → `LocalizedStringResource(…).resolvedInAppLanguage()`.
- `SingleThreadApp+Commands.swift:17` (`About SingleThread`) and `:23` (`Quit SingleThread`)
  → `LocalizedStringResource(…).resolvedInAppLanguage()`.

### 3. macOS MenuBarExtra locale (SingleThreadApp.swift)
`MenuBarExtra` is a sibling of the `WindowGroup`, so its content does not inherit `\.locale`.
Added the environment on the content per the plan snippet:
`MenuBarExtraOptions(store: viewModel.store).environment(\.locale, AppLocaleState.current.effectiveLocale)`
(matches the existing signature/indentation). `Text(due, format: .dateTime)` at
MenuBarExtraOptions.swift:20 then follows the injected locale.

### 4. macOS Commands locale (SingleThreadApp+Commands.swift)
Plan step 3's `.environment(\.locale, …)` **cannot be applied** to macOS `Commands` — verified
against the installed Xcode SwiftUI `swiftinterface`: `environment` exists only on `Scene`,
not on `Commands`/`CommandMenu`/`Button`. Implemented the **minimal equivalent**: the
resource sites are pre-resolved against the app-language preference:
`CommandMenu(SharedStrings.reminder.resolvedInAppLanguage())` and
`Button(SharedStrings.completeReminder.resolvedInAppLanguage())` /
`Button(SharedStrings.skipReminder.resolvedInAppLanguage())` — same pattern Phase 4 used for
non-View sites (`resolvedInAppLanguage()`, nonisolated store read — plan deviation 3).

## Verification results (automated)

| Check | Result |
|---|---|
| `scripts/test-one.sh SingleThreadTests/LocalizationTests` | green — **5 case(s) ran** (catalog-wide invariant now spans 144 App keys) |
| `scripts/test-one.sh SingleThreadTests/SettingsViewTests` | green — **16 case(s) ran** |
| `make format && make lint` | clean — 0 violations, 0 serious (193 files) |
| `rg -n 'String\(localized:' SingleThread SingleThreadCore` | only the helper remains (see below) |

Test runs used the pinned worktree sim `D4C34BCA-7C96-418E-BDD3-BB22738A69C7` (via
`.simulator_id`, inside `scripts/test-one.sh`).

The full `./scripts/test.sh` gate was **not** run (per-phase policy; runs once after Phase 6).

## Residual `String(localized:)` list (exact, after Phase 5)

```
SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:111   (helper: `resolved(in:)` body — must stay)
```

All four Phase 5 scope sites are converted (MenuBarExtraOptions.swift:34,
BackgroundSettingsView.swift:70, SingleThreadApp+Commands.swift:17/23). The plan's
"debug-only exceptions" (`ContentView+iOS.swift:26,28`; `ContentView.swift:331,701,711,721`)
are `Text(...)` literals, not `String(localized:)` calls, so they never appear in this grep
— consistent with the Phase 4 report.

## plan.md
Phase 5 automated checkboxes (lines 1039–1042) flipped `- [ ]` → `- [x]`: LocalizationTests,
SettingsViewTests, `make lint`, and the `String(localized:)` rg sweep. Manual items (1047+),
prior phases, and the Testing-checkpoint table untouched.

## Observations / adaptations
- **`Purchase` key**: `rg '"Purchase"'` across the repo finds **no source literal** in any
  committed code (the only hit is a design doc from the older freemium branch
  `alanvardy-var-642-…`). The design-session note was verified as "missing **as a key**", and
  the task explicitly instructed to add it — done, with six translations, though it has no
  current code consumer (the purchase screen uses `Unlock` / `Restore Purchases` /
  `Manage Purchase`, all already keyed). Reviewers may drop the orphan key later; it is
  invariant-safe either way.
- **Plan step 3 (commands `.environment`)**: not applicable — Commands has no environment
  modifier in the SDK; minimal equivalent (`.resolvedInAppLanguage()`) applied and documented
  above. macOS commands are not covered by the iOS UI test; the plan's macOS manual pass
  verifies the labels switch.
- **macOS-only code is not compile-verified here**: `MenuBarExtraOptions.swift`,
  `SingleThreadApp+Commands.swift`, and the MenuBarExtra env in `SingleThreadApp.swift` are
  `#if os(macOS)`-gated, and the macOS app target is pre-broken on origin/main (per
  instructions — not fixed, mac-build not run). These edits are reviewed by eye; the gate
  subagent / CI mac-tests will compile them.
- **Pre-existing eager `String(localized:)` not in Phase 5 scope**: BackgroundSettingsView.swift:77-79
  (`Photo by \(photographer) on Unsplash`) is a second eager site, but it is broken across two
  lines (`String(\n localized: …)`), so the single-line `rg 'String\(localized:'` misses it.
  It predates Phase 5, is not in the plan's Phase 5 residual list (plan lists only
  BackgroundSettingsView:70), and was left untouched per "Implement ONLY Phase 5 / no
  refactoring". Flagged for a possible Phase 6 hardening pass.
- **macOS Commands Appearance submenu**: the `CommandMenu("Appearance")` /
  `Picker("Appearance", …)` / `Text("System|Light|Dark")` tags in SingleThreadApp+Commands.swift
  are plain string literals (keys exist in the catalog, used by `AppearanceMode.title` on the
  iOS/macOS settings screen). Task item (a) said "no catalog work needed, but verify and report"
  — verified and reported: that native-menu submenu renders English until the tags are
  converted to resources (suggested Phase 6 hardening).

## Next steps
- Phase 6 (hardening) then the single `run-gate` full-suite run.
- macOS manual pass (plan manual item 1047+) should cover the app-menu
  About/Quit/Reminder/Complete/Skip labels and the Appearance submenu.