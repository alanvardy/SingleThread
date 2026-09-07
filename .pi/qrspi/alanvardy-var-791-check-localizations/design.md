# Design Discussion — Localization Audit (VAR-791)

## Current State

The app ships in six locales (en, zh-Hans, es, ja, de, fr) across four `Localizable.xcstrings` catalogs (App: 130 keys, Core: 30, Watch: 4, Widget: 5) and 18 `InfoPlist.strings` files (3 targets × 6 locales).

**Every stringUnit in every catalog is marked `state: "translated"`**, but seven keys have at least one non-English value byte-identical to the English source (research.md §Q1):

| Key | Catalog | Flagged locales |
|---|---|---|
| `%lld%%` | App | all 5 (format string — no words) |
| `SingleThread` | App | all 5 (brand name) |
| `Copyright 2026 Alan Vardy` | App | es, ja, de, fr |
| `System` | App | de only |
| `Interface` | App | fr only |
| `Notifications` | App | fr only |
| `Version %@` | Core | de, fr |

**`InfoPlist.strings` are genuinely translated** except `CFBundleDisplayName = "SingleThread"` (15 instances, brand name — intentional) (research.md §Q2).

**Hardcoded English bypassing catalogs entirely** (research.md §Q4):
- iOS dictation block (`ContentView.swift:663,667,687,692`): `Processing…`, `Processing`(a11y), `Speech recognition is unavailable.`, `Open Settings`
- iOS card (`ReminderCardView.swift:169`): a11y label `Skipped 6 times — tap to manage`
- Watch reschedule sheet (`WatchReminderView.swift:215,295,298,316`): `Reschedule`, `Reschedule to`, `Cancel`
- macOS commands (`SingleThreadApp+Commands.swift:17,23`, `MenuBarExtraOptions.swift:32`): `About SingleThread`, `Quit SingleThread`, `Open SingleThread`

**Shared-key duplication** (research.md §Q1 cross-catalog): `Medium`, `Reminder`, `Complete Reminder`, `Skip Reminder` exist in both App and Core catalogs, violating the `LocalizedString+Shared.swift` convention. `Medium` diverges: App es `Mediano` vs Core es `Media`.

**Existing tests** (`LocalizationTests.swift:20-141`, conventions.md): validate structure only — presence, non-emptiness, plural category membership. Cannot detect English copies. No CI scripting for localization outside this test suite.

## Desired End State

1. **Every non-English xcstrings value that CAN be translated IS translated.** Format strings, brand names, and copyright boilerplate are intentionally English and excluded from the guard.
2. **No hardcoded English** in production or accessibility strings at any call site — every user-visible string resolves through a catalog.
3. **Shared keys live in exactly one catalog** (Core), matching the documented convention. Duplicated App entries are removed; the best translation survives.
4. **A regression test** prevents new English copies from landing. The guard runs in `LocalizationTests`, fails `./scripts/test.sh`, and has an explicit exclusion list for intentional identities.
5. **Verification**: `make test -only-testing:SingleThreadTests/LocalizationTests` passes; `./scripts/test.sh` gate green.

## Patterns to Follow

- **All localization validation lives in `LocalizationTests.swift`** (240 ln, `struct LocalizationTests` at `:17`). New guard goes here, not a scripts/ or Makefile target (conventions.md §test-suite inventory).
- **Catalog paths are hardcoded relative to `repoRoot`** (`LocalizationTests.swift:160-172,166-172`). Use these same paths; do not introduce path discovery.
- **Parsing via `JSONSerialization.jsonObject` + `as? [String: Any]` casts** (`LocalizationTests.swift:24-25`) — no regex, no hand-rolled parser. Match the existing pattern exactly.
- **`InfoPlist.strings` parsing via `PropertyListSerialization.propertyList`** (`LocalizationTests.swift:132-134`). Same approach for any InfoPlist checks.
- **Swift Testing, not XCTest** for unit tests. Function names must NOT start with `test` (conventions.md §unit-test naming).
- **`String(localized:key, table:, bundle:, locale:)`** for runtime lookup (`LocalizationTestHelpers.swift:6-11`). New catalog entries use the same pattern in production code.
- **`Bundle.core`** (`LocalizationTestHelpers.swift:23-30`) resolves embedded `SingleThreadCore_SingleThreadCore.bundle` — use for Core catalog assertions in tests.

### Patterns to AVOID

- The current `hasNonEmptyValue(loc:)` helper (`LocalizationTests.swift:187-219`) never receives the English entry — it is structurally incapable of detecting copies. Do NOT reuse this pattern for the new guard.
- `InfoPlist.strings` values are genuinely translated except the brand name — do NOT add a blanket identity-check to the `.lproj` test; the issue is xcstrings only.
- The `state: "translated"` field carries zero signal (everything is `"translated"`). Do NOT gate on `state` — gate on actual value comparison.

## Design Decisions

1. **Regression guard location**: Test-time only, in `LocalizationTests.swift`. Reuses existing catalog paths + `JSONSerialization` parser + `-only-testing:SingleThreadTests/LocalizationTests` gate. No CI script, no Makefile target, no `jq`. Matches established pattern (research.md §Q3).

2. **Intentional-identity exclusions**: A static exclusion list of `(catalog, key)` tuples that the guard skips. Current entries: `%lld%%`, `SingleThread` (App); `Copyright 2026 Alan Vardy`. If future keys are intentionally English, add to the list — the CI failure is the prompt to decide. No runtime heuristic.

3. **Hardcoded string remediation — scope**: Fix ALL user-visible hardcoded English strings, not just watch. This includes iOS dictation, iOS a11y labels, watch reschedule sheet, and macOS commands. Each gets a new entry in the appropriate catalog; call sites switch to `String(localized:)` or `Text` literal (SwiftUI automatic lookup). macOS commands are `#if os(macOS)` code — their catalog entries need macOS-test verification or a manual attestation note.

4. **Shared-key deduplication**: Remove `Medium`, `Reminder`, `Complete Reminder`, `Skip Reminder` from the App catalog. For each, audit which translation is correct per locale and ensure the Core catalog has it. The `Medium` es divergence (`Mediano` vs `Media`) must be resolved — audit call sites to determine whether the App or Core context is authoritative. Watch/Widget catalog copies of shared keys stay (single-catalog per target, no `.module` fallback in those targets — research.md shows they resolve via their own main-bundle), but verify they match Core translations.

5. **Translation values**: The design specifies WHICH keys need fixing, not the exact translated strings. Implementer chooses translations using Apple HIG/localization conventions for well-known UI terms (`Interface` in French computing terminology is already correct — this may be a false positive to validate rather than blindly change).

6. **Plural handling**: The 5 `%lld` plural keys are genuinely distinct across locales (research.md §Q1 variations.plural). No changes needed. The de/fr `one`-form oddities (`Alle %lld Tag`, `Tous les %lld jour`) are pre-existing form-quality observations — not regressions, not in scope.

7. **`InfoPlist.strings` scope**: No changes. All non-brand-name entries are genuinely translated (research.md §Q2). The regression guard targets xcstrings catalogs only.

## What We're NOT Doing

- **NOT translating brand names or format-only strings** (`%lld%%`, `SingleThread`). These are in the exclusion list.
- **NOT adding CI scripting** (no `jq`, no Python, no Makefile target). Everything stays in `LocalizationTests.swift`.
- **NOT touching Watch/Widget catalogs** (4 and 5 keys, all genuinely distinct — research.md §Q1). Exception: #4 dedup may touch Widget if its `Complete Reminder`/`Skip Reminder` copies diverge from Core after App dedup.
- **NOT changing plural structure** (category membership, form text). The 5 plural keys are correct.
- **NOT introducing a localization automation pipeline** (`xcstringstool`, `xcodebuild -exportLocalizations`). Future task.
- **NOT fixing the macOS `About SingleThread`/`Quit SingleThread` translations** in a way that requires macOS build verification — add catalog entries and use `String(localized:)`; if `#if os(macOS)` prevents local testing, note it for on-device verification.

## Open Risks

- **de `System` and fr `Interface`** may be computing-cognate false positives — `System` and `Interface` are the standard German and French UI terms for those concepts. The implementer must validate before changing; if they ARE correct, the exclusion list grows.
- **`Medium` es divergence** (`Mediano` vs `Media`): depends on which call site resolved through which bundle. If both bundles serve different UI contexts, the "correct" translation may differ — dedup may need to split into two differently-keyed entries.
- **Watch reschedule strings** currently bypass the catalog even though the watch already has a `Localizable.xcstrings`. Adding entries and switching to `Text` literals should Just Work (SwiftUI auto-lookup against main bundle), but the watch catalog is currently 4 keys — verify the watch build succeeds.
- **macOS code paths** (`SingleThreadApp+Commands.swift`, `MenuBarExtraOptions.swift`) may not build in an iOS-only `xcodebuild` invocation. If they're `#if os(macOS)` gated, the catalog entries compile but the call-site changes are unreachable in local tests — mark for manual verification.
- **The existing `LocalizationTests.swift` test `infoPlistStringsHaveRequiredKeysPerLanguage`** (`:124-141`) does not check for English-equal values. If we add a guard that walks catalogs only, `.lproj` identical-brand-name remains OK (by design). If future `.lproj` entries regress to English, the guard won't catch it — acceptable scope tradeoff.