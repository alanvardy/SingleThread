# Research Questions

## Context

This repo contains an iOS app, a watchOS app, a widget extension, and a shared
SPM Swift package. Localized content lives in four `Localizable.xcstrings`
string catalogs (one per product) plus per-locale `InfoPlist.strings` files,
all covering the same six locales (en, zh-Hans, es, ja, de, fr). Focus on the
translation content itself, how it is structured, how it is resolved at
runtime, and how it is currently validated and inspected.

## Questions

1. **Key-level translation state in the string catalogs.** For each of the four
   `Localizable.xcstrings` catalogs (App, Core, Watch, Widget), enumerate every
   key where a non-English locale's value is identical to the English source
   (or trivially similar, e.g. the same text with only punctuation/case
   differences), reported per catalog and per locale with the exact key string.
   Distinguish plain UI text from format strings (`%lld`, `%@`, `%1$@`),
   proper nouns, and product names. Also examine `variations.plural` entries:
   are plural forms genuinely distinct per language?

2. **InfoPlist.strings translation state.** For all 18 `.lproj/InfoPlist.strings`
   files (3 targets × 6 locales), list every key and its current value in each
   locale, and flag any locale values that are identical to the English source.
   Note any files that are missing keys, use malformed `.strings` syntax, or
   contain non-ASCII characters that might indicate encoding issues.

3. **Existing localization validation and test infrastructure.** What exactly
   does `SingleThreadTests/LocalizationTests.swift` assert today, and how does
   it parse the `.xcstrings` JSON and `.lproj` files (parsers, helpers,
   hardcoded paths)? Could the current assertions detect a translation that is
   an exact English copy, and if not, which existing infrastructure
   (`LocalizationTestHelpers.swift`, the `String.en(...)` helper, bundle
   loading) could a new validation reuse?

4. **Runtime resolution and fallback behavior.** How do the app, watch, and
   widget resolve `String(localized:)` calls at runtime — what are the
   `bundle:` (`main` vs `module`) and `table:` semantics, and which keys are
   shared via `LocalizedString+Shared.swift`? When a locale value is missing or
   equals the English key, does the runtime silently fall back to the source
   language? Are there any user-facing hardcoded English strings in Swift code
   that bypass the catalogs entirely?

5. **Tooling available for inspecting the catalogs.** What mechanisms exist in
   this environment to read, parse, or export the catalog contents (e.g.
   `xcodebuild -exportLocalizations` / `-importLocalizations`,
   `xcstringstool`, Xcode's string catalog editor, `plutil`/JSON
   serialization)? Is there any existing script, Makefile target, CI step, or
   documentation that touches localization, and what catalog schema version
   and `extractionState` do the files declare?