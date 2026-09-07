# Structure Outline

## Approach

Build the localization audit fix bottom-up: a regression guard first, then catalog content fixes, then hardcoded-string remediation. Every layer ships with its tests green before the next layer starts. If any layer fails, the completed layers remain independently valuable and can land on their own.

---

## Stage 1: Guard Infrastructure + Exclusion List

**What this layer delivers**: A new test in `LocalizationTests` that flags any non-English xcstrings value byte-identical to the English source, minus a static exclusion list for intentional identities. Once green, every subsequent catalog edit is protected against regression.

**Files**:
- `SingleThreadTests/LocalizationTests.swift`

**Key changes**:
- `ExclusionEntry` — private struct or typealias `( catalog: String, key: String)`
- `excludedIdentities: Set<ExclusionEntry>` — static constant, populated with the 3 intentional-identity tuples:
  - `("App","%lld%%")`
  - `("App","SingleThread")`
  - `("App","Copyright 2026 Alan Vardy")`
- New `@ Test` function — walks `Self.catalogs` (App + Coreonly; Watch/Widget are clean per research), extracts `localizations.en.stringUnit.value` as the source, compares each non-English `stringUnit.value` byte-for-byte, skips entries in `excludedIdentities`, and `#expect`s they differ
- Plural keys: compare each `variations.plural.<category>.stringUnit.value` against the English source for that same category

**Tests to write/run**: The guard itself is the test. After writing it:
1. Run `- only-testing:SingleThreadTests/LocalizationTests` — expects ~14 failures (all 19 flags from research, except the 3 already in the exclusion list)
2. Validate the `de System` and `fr Interface` / `fr Notifications` false-positive question: if they ARE correct computing cognates, add to exclusion list:
   - `("App","System")` (de)
   - `("App","Interface")` (fr)
   - `("App","Notifications")` (fr)
3. Also validate `Version %@ "` in de/fr — "Version" is the same word in German and French. If intentional, add `("Core","Version %@ ")` to exclusions
4. After exclusion list is complete, `- only-testing:SingleThreadTests/LocalizationTests` must be **fully green**

**Verify**: `xcodebuild -scheme SingleThread -destination "platform=iOS Simulator,name=iPhone 17,OS=latest" test -only-testing:SingleThreadTests/LocalizationTests` passes with zero failures

---

## Stage2: Catalog Fixes — Flagged Translations

**What this layer delivers**: Remaining flagged keys (those not in the exclusion list) fixed with real translations in the xcstrings catalogs. After this layer, the guard from Stage1 is green with zero failures — every non-excluded non-English value differs from English.

**Files**:
- `SingleThread/Resources/Localizable.xcstrings`
- `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`

**Key changes** (xcstrings JSON edits — no Swift type changes):
- App catalog: `Copyright 2026 Alan Vardy` → es/ja/de/fr get translated values (zh-Hans already translated; `Alan Vardy` stays as proper noun, boilerplate text gets locale-appropriate translations)
- App catalog: `System` (de) → if NOT in exclusion list, provide German translation
- App catalog: `Interface` (fr) → if NOT in exclusion list, provide French translation
- App catalog: `Notifications` (fr) → if NOT in exclusion list, provide French translation
- Core catalog: `Version %@ ` (de, fr) → if NOT in exclusion list, provide translations

**Tests**: The Stage1 guard re-runs and goes from "partially failing" (exclusions only) to "fully green" (exclusions + real translations both pass identity check)

**Verify**: `- only-testing:SingleThreadTests/LocalizationTests` green; `make build` succeeds

---

## Stage3: Shared-Key Deduplication

**What this layer delivers**: `Medium`, `Reminder`, `Complete Reminder`, `Skip Reminder` exist only in the Core catalog; App duplications are removed. The best translation survives per locale. The `Medium` es divergence (`Mediano` vs `Media`) is resolved.

**Files**:
- `SingleThread/Resources/Localizable.xcstrings` (remove 4 keys)
- `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` (ensure correct translations)
- Possibly: `LocalizedString+Shared.swift` if any shared-key accessor is found to resolve through the wrong bundle (audit only)

**Key changes**:
- Audit call sites for `Medium`, `Reminder`, `Complete Reminder`, `Skip Reminder` to determine which bundle each resolves through. All should resolve through Core (`bundle: .module`); verify no call site directly references the App catalog for these keys
- Remove the 4 keys from App catalog. For each, ensure the Core catalog entry has the correct translation in every locale
- Resolve `Medium` es divergence: if both App and Core `Medium` serve the same UI context, pick one translation; if they serve different contexts, create a second distinctly-keyed entry in Core
- Audit Watch/Widget catalog copies of shared keys: verify they match Core translations. If they diverge, correct them

**Tests**: Stage1 guard re-runs — must stay green (removed duplicate keys can't regress the guard; corrected translations stay non-identical to English)

**Verify**: `- only-testing:SingleThreadTests/LocalizationTests` green; `make build` (ios + watch) succeeds; manual spot-check of `Medium` call sites in the running app

---

## Stage4: Hardcoded String Remediation — Catalog Entries

**What this layer delivers**: New catalog entries for every hardcoded English string, with translations for all 6 locales. The Stage1 guard stays green (new entries are translated, not English copies).

**Files**:
- `SingleThread/Resources/Localizable.xcstrings` — new entries
- `SingleThreadWatch/Resources/Localizable.xcstrings` — new entries for watch-only strings

**New catalog keys**:

| Key | Catalog | Notes |
|---|---|---|
| `Processing… ` | App | dictation progress indicator |
| `Processing` | App | a11y label for dictation progress |
| `Speech recognition is unavailable.` | App | dictation error |
| `Open Settings` | App | dictation error recovery button |
| `Skipped %lld times — tap to manage` | App | a11y label on ReminderCardView; format string for count |
| `Reschedule` | Watch | reschedule sheet title |
| `Reschedule to` | Watch | reschedule sheet prompt |
| `Cancel` | Watch | reschedule sheet dismiss; may already exist in Core as a shared key — check before adding |
| `About SingleThread` | App | macOS menu; `#if os(macOS)` only |
| `Quit SingleThread` | App | macOS menu; `#if os(macOS)` only |
| `Open SingleThread` | App | macOS menu bar; `#if os(macOS)` only |

**Translations**: Implementer provides locale-appropriate translations for all6 locales (en, zh-Hans, es, ja, de, fr). `SingleThread` stays English (brand name) embedded in translated surrounding text.

**Tests**: Stage1 guard re-runs — new entries must have non-English values that differ from English source; if any new entry is a cognate identical to English in some locale, add to exclusion list with a comment

**Verfy**: `- only-testing:SingleThreadTests/LocalizationTests` green; `make build` + `make watch-build` both succeed

---

## Stage5: Hardcoded String Remediation — Call Sites

**What this layer delivers**: Every hardcoded English literal in production and accessibility code switches to catalog-backed lookup. Zero user-visible strings bypass the localization system.

**Files**:
- `SingleThread/ContentView.swift` (`:663,667,687,692` — dictation block)
- `SingleThread/ReminderCardView.swift` (`:169` — a11y label)
- `SingleThreadWatch/WatchReminderView.swift` (`:215,295,298,316` — reschedule sheet)
- `SingleThread/SingleThreadApp+Commands.swift` (`:17,23` — macOS About/Quit)
- `SingleThread/MenuBarExtraOptions.swift` (`:32` — macOS Open)

**Key changes**:
- iOS dictation: replace `Text("Processing… ")` with `Text("Processing… ", tableName: "Localizable", bundle: .main)` or plain `Text` literal (SwiftUI auto-lookup); same for a11y label and error strings
- iOS a11y: replace `.accessibilityLabel("Skipped 6times — tap to manage")` with a format-string lookup using `String(localized: "Skipped %lld times — tap to manage", defaultValue: ..., bundle: .main)` and interpolate the skip count
- Watch reschedule: replace `Text("Reschedule")`, `Text("Reschedule to")`, `Text("Cancel")` with `Text` literals — SwiftUI auto-lookup against watch main-bundle `Localizable` (matches existing pattern for watch `Text` literals)
- macOS commands: replace hardcoded strings with `String(localized:key, bundle: .main)`. If `#if os(macOS)` prevents local test compilation, mark for manual on-device verification

**Pattern**: Use `String(localized:)` for `Button` titles and a11y labels where the key isn't a SwiftUI `Text` literal; use plain `Text("Key")` for `Text` views (SwiftUI auto-lookup). Match existing patterns: app call sites use `bundle: .main`, Core shared strings use `bundle: .module`.

**Tests**: Existing suite must stay green. No new unit tests required (the Stage1 guard already proves the catalog entries exist and are translated; call-site changes are wiring). Manual verification: run the app and confirm dictation error, a11y label, and reschedule sheet show translated text in a non-English locale

**Verify**: `make build` + `make watch-build` + `make test` (unit only) all green; manual spot-check in Spanish or German locale on simulator

---

## Stage6: Final Gate

**What this layer delivers**: Full CI-identical gate green — proof that nothing was broken.

**Verify**: `./scripts/test.sh` passes (format, lint, build, Periphery, unit + UI tests). Run detached: `nohup bash ./scripts/test.sh > /tmp/gate.log 2>&1 &`

---

## Testing Checkpoints

After each stage, these must be green before advancing:

| Stage | Checkpoint |
|---|---|
|1 | `- only-testing:SingleThreadTests/LocalizationTests` — exclusion-only failures resolved to green |
|2 | `- only-testing:SingleThreadTests/LocalizationTests` — zero failures; `make build` |
|3 | `- only-testing:SingleThreadTests/LocalizationTests` green; `make build` + `make watch-build` |
|4 | `- only-testing:SingleThreadTests/LocalizationTests` green; `make build` + `make watch-build` |
|5 | `make build` + `make watch-build` + `make test` (unit only) |
|6 | `./scripts/test.sh` green |

---

## Cross-Cutting Notes

- **Watch/Widget catalogs are out of scope for the guard** (research confirms zero English-identity flags in those 9 keys). Stage4 adds new Watch entries — those ARE covered by the guard since they're new additions.
- **`InfoPlist.strings` are out of scope** per design decision 7 — no changes, no guard. The brand-name `CFBundleDisplayName = "SingleThread"` is intentional across all 15 non-English instances.
- **macOS code paths may not build locally** (`#if os(macOS)`). Stage5 catalog entries still compile everywhere; call-site changes in `SingleThreadApp+Commands.swift` and `MenuBarExtraOptions.swift` need a note for manual macOS verification.
- **`Cancel` dedup check in Stage4**: if `Cancel` already exists as a shared key in Core (`LocalizedString+Shared.swift`), add the Watch entry but use the Core translation text — or switch the Watch call site to resolve through Core's `.module` bundle. Audit during Stage4, not before.