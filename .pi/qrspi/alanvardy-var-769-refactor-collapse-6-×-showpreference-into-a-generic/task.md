# VAR-769 — Collapse the six `Show*Preference` structs into a generic `BoolPreferenceStore`

## Task

Collapse the six near-identical `Show*Preference` structs in `SingleThreadCore` (`ShowDatePreference`, `ShowListPreference`, `ShowRecurrencePreference`, `ShowAlarmsPreference`, `ShowCompletionGlowPreference`, `ShowUndatedRemindersPreference`) into a single generic `BoolPreferenceStore` parameterized by key and default fallback value, following the shape of `SortOptionStore`. Each key's distinct absent-value fallback and its current read/write behavior must be preserved across the iOS app, watchOS app, widget, and sync service.

## Why

The VAR-759 state audit (finding T4.4) identified six duplicated hand-written preference structs with per-key fallback values that already diverge. One generic store removes the duplication while keeping behavior identical.

## Acceptance

One generic store replaces the six structs; all six keys round-trip identically under unit tests (including the four `true`-default and two `false`-default fallbacks, and custom-key injection); no user-visible behavior change when the full CI gate (`./scripts/test.sh`) passes.