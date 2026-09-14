# Task

Flip the `enableActionButtons` setting default from `false` to `true` so a fresh install shows the Complete/Skip/Reschedule action cluster over the reminder card without any settings change. The **Settings → Interface → Show action buttons** toggle stays and must still turn the cluster off, with that off state persisting (App Group + watch sync unchanged).

Scope — the four mirrored default sites that must move together:

1. `SingleThread/ContentView.swift:101` — `@AppStorage("enableActionButtons", store: AppGroup.defaults) var enableActionButtons = false` → default `true`
2. `SingleThread/ContentViewModel.swift:77` — view mirror `var enableActionButtons = false` → default `true` (must track the real default)
3. `SingleThread/SettingsBindings.swift:31` — `enableActionButtons: Bool = false` default argument → `true`
4. `SingleThreadWatch/ShowEnableActionButtonsState.swift:15` — raw `AppGroup.defaults.bool(forKey:)` read; an absent key currently reads `false`, so add an explicit fallback to `true` so the watch shows the cluster by default on fresh installs

Decision (made in the ticket, ⭐): **fresh installs only** — do NOT migrate existing users. The one-time `AppViewModel.registerDefaults()` `.standard` copy stays as-is and must still not clobber an existing App Group value.

Acceptance criteria:
- A fresh install (no stored key) shows the Complete/Skip cluster with no settings change (iOS and watch).
- The toggle still turns it off, and the off state persists (App Group + watch sync behaviour unchanged).
- Unit tests cover the new default and the sad path (explicitly toggled off stays off), on both iOS and watch sides.
- The `--ui-testing` / `--seed` seams that force it on keep working.

## Why MEDIUM
Breadth triggers 7 + 9: the change spans two platform targets (iOS app + watchOS app) with diverging default mirrors, but an established cross-target pattern (the ticket documents the exact four sites and the mirror-tracking rule) carries it end to end. M1/M2 hold — approach known with near-zero unknowns and no schema/migration/design decision (the one open question, existing installs, is pre-resolved in the ticket).

## Key files
- `SingleThread/ContentView.swift` (~101) — `@AppStorage` declaration, source of truth
- `SingleThread/ContentViewModel.swift` (~77) — view mirror
- `SingleThread/SettingsBindings.swift` (~31) — settings default argument
- `SingleThreadWatch/ShowEnableActionButtonsState.swift` (~15) — watch read; needs explicit fallback
- `AppViewModel.registerDefaults()` — verify the one-time `.standard` copy still does not clobber; comment may need updating
- Existing unit-test seams: `--ui-testing` / `--seed` launch args (per repo AGENTS.md they persist via `AppGroup.defaults`)