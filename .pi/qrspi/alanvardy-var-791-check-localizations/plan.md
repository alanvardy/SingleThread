# Implementation Plan — Localization Audit Fix (VAR-791)

## Overview

Eliminate English-identity translations and hardcoded English strings. A new regression guard in `LocalizationTests` catches future English copies; catalog entries are fixed with real translations; shared keys deduplicate into Core; and all hardcoded user-visible strings switch to catalog-backed lookups.

---

## Phase 1: Guard Infrastructure + Exclusion List

### Changes

#### 1. New `LocalizationTests.swift` test — `nonEnglishValuesDifferFromEnglish`
**File**: `SingleThreadTests/LocalizationTests.swift`
**Action**: modify (add one new `@Test` function + supporting types)

Add after the existing `infoPlistStringsHaveRequiredKeysPerLanguage` test (before the `// MARK: Private` line at `:143`):

```swift
// MARK: - Regression guard

/// Every non-English value in the App and Core catalogs must differ from the
/// English source. Intentional identities (brand names, format strings, and
/// validated computing cognates) are listed in `excludedIdentities`.
///
/// Watch and Widget catalogs are excluded — research confirms zero
/// English-identity flags in their 4 / 5 keys.
@Test
func nonEnglishValuesDifferFromEnglish() throws {
    for (name, url) in Self.guardedCatalogs {
        let data = try Data(contentsOf: url)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        for (key, value) in strings {
            let entry = try #require(value as? [String: Any], "\(name)/\(key) malformed")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let enEntry = try #require(localizations["en"] as? [String: Any], "\(name)/\(key) missing en")
            for language in Self.nonEnglishLanguages {
                guard let loc = localizations[language] as? [String: Any] else {
                    continue
                }
                if Self.excludedIdentities.contains(ExclusionEntry(catalog: name, key: key)) {
                    continue
                }
                if let unit = loc["stringUnit"] as? [String: Any] {
                    let enValue = try englishValue(from: enEntry, key: key, catalog: name)
                    let locValue = try #require(unit["value"] as? String,
                        "\(name)/\(key) \(language) stringUnit has no value")
                    #expect(
                        locValue != enValue,
                        "\(name)/\(key) \(language) value is identical to English: \"\(locValue)\"")
                } else if let variations = loc["variations"] as? [String: Any],
                          let plural = variations["plural"] as? [String: Any] {
                    let enVariations = try #require(enEntry["variations"] as? [String: Any],
                        "\(name)/\(key) en missing variations for plural comparison")
                    let enPlural = try #require(enVariations["plural"] as? [String: Any],
                        "\(name)/\(key) en missing plural for plural comparison")
                    for (category, variation) in plural {
                        guard let variant = variation as? [String: Any],
                              let unit = variant["stringUnit"] as? [String: Any],
                              let locValue = unit["value"] as? String else { continue }
                        guard let enVariant = enPlural[category] as? [String: Any],
                              let enUnit = enVariant["stringUnit"] as? [String: Any],
                              let enValue = enUnit["value"] as? String else { continue }
                        #expect(
                            locValue != enValue,
                            "\(name)/\(key) \(language) plural \(category) is identical to English: \"\(locValue)\"")
                    }
                }
            }
        }
    }
}
```

Add these private helpers alongside the existing `// MARK: Private` section:

```swift
/// Catalogs guarded against English-identity translations.
private static let guardedCatalogs: [(name: String, url: URL)] = [
    catalogs[0], // Core
    catalogs[1]  // App
]

/// All non-English languages.
private static let nonEnglishLanguages = ["zh-Hans", "es", "ja", "de", "fr"]

/// A key identity within a specific catalog.
private struct ExclusionEntry: Hashable {
    let catalog: String
    let key: String
}

/// Keys whose non-English value may be byte-identical to the English source.
/// Format strings, brand names, and validated computing cognates.
private static let excludedIdentities: Set<ExclusionEntry> = [
    ExclusionEntry(catalog: "App", key: "%lld%%"),
    ExclusionEntry(catalog: "App", key: "SingleThread"),
    ExclusionEntry(catalog: "App", key: "Copyright 2026 Alan Vardy"),
    // de "System" — standard German computing term, same spelling as English
    ExclusionEntry(catalog: "App", key: "System"),
    // fr "Interface" — standard French computing term, same spelling as English
    ExclusionEntry(catalog: "App", key: "Interface"),
    // fr "Notifications" — standard French UI term, same spelling as English
    ExclusionEntry(catalog: "App", key: "Notifications"),
    // de/fr "Version" — same spelling in German and French
    ExclusionEntry(catalog: "Core", key: "Version %@ ")
]

/// Extracts the English `stringUnit.value` from an en localization entry.
/// Handles both direct stringUnit keys and keys nested under variations.plural.
private static func englishValue(from enEntry: [String: Any], key: String, catalog: String) throws -> String {
    if let unit = enEntry["stringUnit"] as? [String: Any] {
        return try #require(unit["value"] as? String,
            "\(catalog)/\(key) en stringUnit has no value")
    }
    // For plural-only keys, return the en `other` category value as the canonical form.
    if let variations = enEntry["variations"] as? [String: Any],
       let plural = variations["plural"] as? [String: Any],
       let otherVariant = plural["other"] as? [String: Any],
       let otherUnit = otherVariant["stringUnit"] as? [String: Any] {
        return try #require(otherUnit["value"] as? String,
            "\(catalog)/\(key) en plural other has no value")
    }
    throw NSError(domain: "LocalizationTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "\(catalog)/\(key) en has no extractable value"])
}
```

#### 2. Fix exclusion key: `Version %@ ` trailing space

The Core catalog key has a trailing space: `Version %@ ` (confirmed in xcstrings at line `:1310`). The exclusion entry must match exactly. If a whitespace-only mismatch causes a failure, adjust the exclusion key to match the exact catalog key.

### Verification

#### Automated
- [x] Run `SIM='platform=iOS Simulator,name=iPhone 17,OS=latest' xcodebuild -scheme SingleThread -destination "$SIM" test -only-testing:SingleThreadTests/LocalizationTests/nonEnglishValuesDifferFromEnglish` — expect 0 failures (all flagged keys are in `excludedIdentities`)

#### Manual
- [ ] Validate `de System`, `fr Interface`, `fr Notifications` are correct computing cognates before locking them into exclusion list — they are standard UI terms but verify with a native-speaker check if available

---

## Phase 2: Catalog Fixes — Flagged Translations

### Changes

#### 1. Fix `Copyright 2026 Alan Vardy` — es, ja, de, fr
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (update 4 `stringUnit.value` entries)

Key is at `:455`. Replace the 4 byte-identical English values:

| Locale | Current (English copy) | New value |
|--------|----------------------|-----------|
| es | `Copyright 2026 Alan Vardy` | `Derechos de autor 2026 Alan Vardy` |
| ja | `Copyright 2026 Alan Vardy` | `著作権 2026 Alan Vardy` |
| de | `Copyright 2026 Alan Vardy` | `Urheberrecht 2026 Alan Vardy` |
| fr | `Copyright 2026 Alan Vardy` | `Droits d'auteur 2026 Alan Vardy` |

zh-Hans is already translated (`版权所有 2026 Alan Vardy` at `:467`) — no change.

#### 2. Fix `Version %@ ` — de, fr (if NOT in exclusion list)
**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify (update 2 `stringUnit.value` entries, or if validated as cognates, verify exclusion list entry)

Key is at `:1310`. If `Version` is a valid cognate in de/fr (same spelling, standard computing term):
- Confirm `ExclusionEntry(catalog: "Core", key: "Version %@ ")` is in the exclusion list (Phase 1 step 2 ensures the exact key matches)
- No catalog change needed

If NOT a valid cognate (unlikely — "Version" is the standard German and French spelling):

| Locale | Current (English copy) | New value |
|--------|----------------------|-----------|
| de | `Version %@ ` | `Version %@ ` (same — cognate) |
| fr | `Version %@ ` | `Version %@ ` (same — cognate) |

The de/fr values are already in the exclusion list per Phase 1. No catalog edits expected for this key.

#### 3. Validate `System` (de), `Interface` (fr), `Notifications` (fr) cognate status

These are already in the exclusion list from Phase 1. If validated as intentional computing-cognates:
- No catalog changes needed for these keys
- Exclusion list entries are sufficient

If any proves to be a genuine mistranslation (unlikely — "System", "Interface", "Notifications" are standard UI terms in German/French computing):
- Remove from exclusion list
- Provide real translations (e.g., de "System" could optionally be "Systemeinstellungen" if the context is settings)

**Assessment**: These are almost certainly correct cognates. Standard German "System" and French "Interface"/"Notifications" are the accepted UI terms. The plan assumes they stay in the exclusion list.

### Verification

#### Automated
- [x] `SIM='platform=iOS Simulator,name=iPhone 17,OS=latest' xcodebuild -scheme SingleThread -destination "$SIM" test -only-testing:SingleThreadTests/LocalizationTests/nonEnglishValuesDifferFromEnglish` — 0 failures (exclusion list covers all intentional identities; `Copyright` translations make the rest differ)
- [x] `make build` succeeds

#### Manual
- [ ] Confirm exclusion list comment accurately describes each entry's justification

---

## Phase 3: Shared-Key Deduplication

### Changes

#### 1. Audit: `Medium` serves two different UI contexts — keep both catalogs separate

**Finding** (confirmed during plan authoring):
- App `Medium` → `TextSize.swift:44`, `bundle: .main` — font size picker. es: "Mediano" (masculine for "tamaño"/size)
- Core `Medium` → `ReminderSkip.swift:43`, `bundle: .module` — priority level. es: "Media" (feminine for "prioridad"/priority)

These are **homonyyms serving different UI contexts** with different required translations in Spanish. The design's goal of "one key in Core" would require splitting into two distinctly-keyed entries, which would change the English user-visible text.

**Decision**: Keep `Medium` in both catalogs. They are not duplicates — they are the same English word used in two semantically different contexts with different translations. Document this in the exclusion list comment and in `LocalizedString+Shared.swift` as a note.

**No catalog changes** for `Medium`. The exclusion list already covers the App `Medium` key's identity with English (all 5 non-English locales are already genuinely translated — research confirms no English-identity flags on `Medium` in either catalog).

#### 2. Remove `Reminder` from App catalog, add to Core catalog

**File**: `SingleThread/Resources/Localizable.xcstrings` 
**Action**: modify (remove the `"Reminder"` key and its localizations block)

**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify (add `"Reminder"` key with all 6 locale translations)

Copy the existing App translations (all locales already genuine — confirmed in research):
- en: "Reminder"
- zh-Hans: "提醒"
- es: "Recordatorio"
- ja: "リマインダー"
- de: "Erinnerung"  
- fr: "Rappel"

**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify (add new accessor after `Complete` at `:14`, before `Skip` at `:16`)

```swift
/// "Reminder" — used by confirmation dialogs, navigation titles, and macOS command menus.
static var reminder: String {
    String(localized: "Reminder", table: "Localizable", bundle: .module)
}
```

**File**: `SingleThread/ContentView+ActionMenu.swift` (`:46`)
**Action**: modify

```swift
// Before:
.confirmationDialog("Reminder", isPresented: $isShowingActionMenu) {
// After:
.confirmationDialog(SharedStrings.reminder, isPresented: $isShowingActionMenu) {
```

**File**: `SingleThread/ReminderSettingsView.swift` (`:94`)
**Action**: modify

```swift
// Before:
.navigationTitle("Reminder")
// After:
.navigationTitle(SharedStrings.reminder)
```

**File**: `SingleThread/SettingsView.swift` (`:88`)
**Action**: modify

```swift
// Before:
title: "Reminder",
// After:
title: SharedStrings.reminder,
```

**File**: `SingleThread/SingleThreadApp+Commands.swift` (`:28`)
**Action**: modify (macOS-only, #if os(macOS) gated)

```swift
// Before:
CommandMenu("Reminder") {
// After:
CommandMenu(SharedStrings.reminder) {
```

**Watch catalog**: Keep the Watch catalog's `"Reminder"` entry unchanged — Watch resolves through its own main bundle via SwiftUI literal lookup. The Watch translations match App/Core translations (confirmed identical: zh-Hans "提醒", es "Recordatorio", ja "リマインダー", de "Erinnerung", fr "Rappel"). The Watch call site (`WatchReminderView.swift:277`) uses `.confirmationDialog("Reminder", ...)` — SwiftUI literal lookup resolves against the Watch main bundle, which has the key.

#### 3. Resolve `Complete Reminder` / `Complete reminder` case divergence

**Finding**: The App catalog has `"Complete Reminder"` (uppercase R), the Core catalog has `"Complete reminder"` (lowercase r). These are **different keys** due to casing, but all locale translations are identical.

**Decision**: 
- Add `"Complete Reminder"` (uppercase R) to Core catalog with the same translations (copy from App)
- Remove `"Complete Reminder"` from App catalog  
- Add `static var completeReminder: String` to `LocalizedString+Shared.swift` (uppercase-R key)
- Keep `"Complete reminder"` (lowercase r) in Core — used by `LocalizedString+Shared.swift` `Complete` accessor for completion-glow contexts
- Update macOS call sites to use the shared accessor

**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify (add new `"Complete Reminder"` key with 6-locale translations from App)

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (remove `"Complete Reminder"` key)

**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify (add after `Complete` accessor)

```swift
/// "Complete Reminder" (title case) — used by macOS command menus and menu bar.
static var completeReminder: String {
    String(localized: "Complete Reminder", table: "Localizable", bundle: .module)
}
```

**File**: `SingleThread/SingleThreadApp+Commands.swift` (`:29`) — macOS-only
**Action**: modify

```swift
// Before:
Button("Complete Reminder") {
// After:
Button(SharedStrings.completeReminder) {
```

**File**: `SingleThread/MenuBarExtraOptions.swift` (`:25`) — macOS-only
**Action**: modify

```swift
// Before:
Button("Complete Reminder") {
// After:
Button(SharedStrings.completeReminder) {
```

**Widget catalog**: Keep `"Complete Reminder"` in Widget catalog — Widget resolves through its own main bundle. The translations match.

#### 4. Resolve `Skip Reminder` / `Skip reminder` case divergence

Same pattern as Complete Reminder — different keys via casing, identical translations.

**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify (add new `"Skip Reminder"` key with 6-locale translations from App)

**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (remove `"Skip Reminder"` key)

**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify (add after `Skip` accessor area)

```swift
/// "Skip Reminder" (title case) — used by macOS command menus and menu bar.
static var skipReminder: String {
    String(localized: "Skip Reminder", table: "Localizable", bundle: .module)
}
```

**File**: `SingleThread/SingleThreadApp+Commands.swift` (`:36`) — macOS-only
**Action**: modify

```swift
// Before:
Button("Skip Reminder") {
// After:
Button(SharedStrings.skipReminder) {
```

**File**: `SingleThread/MenuBarExtraOptions.swift` (`:28`) — macOS-only
**Action**: modify

```swift
// Before:
Button("Skip Reminder") {
// After:
Button(SharedStrings.skipReminder) {
```

**Widget catalog**: Keep `"Skip Reminder"` in Widget catalog.

### Verification

#### Automated
- [ ] `SIM='platform=iOS Simulator,name=iPhone 17,OS=latest' xcodebuild -scheme SingleThread -destination "$SIM" test -only-testing:SingleThreadTests/LocalizationTests/nonEnglishValuesDifferFromEnglish` — 0 failures (guard stays green; new Core entries are translated)
- [ ] `make build` succeeds (iOS)
- [ ] `make watch-build` succeeds (Watch keeps its own `"Reminder"` key)
- [ ] `make test` (unit only) — verify `ReminderSkipTests` (`.core` bundle for `Medium`) and `TextSizeTests` (`.main` bundle for `Medium`) both pass

#### Manual
- [ ] Spot-check: navigate to Reminder settings, action menu — "Reminder" still displays correctly in English locale
- [ ] macOS paths: `SingleThreadApp+Commands.swift` and `MenuBarExtraOptions.swift` changes are `#if os(macOS)` — marked for on-device macOS verification; catalog entries and shared accessors compile on iOS

---

## Phase4: Hardcoded String Remediation — Catalog Entries

### Changes

#### 1. App catalog — new dictation entries
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (add 4 new keys before the closing `}` of the `"strings"` dict)

Add entries for:

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Processing…` | Processing… | 处理中… | Procesando… | 処理中… | Verarbeitung… | Traitement en cours… |
| `Processing` | Processing | 处理 | Procesando | 処理 | Verarbeitung | Traitement |
| `Speech recognition is unavailable.` | Speech recognition is unavailable. | 语音识别不可用。 | El reconocimiento de voz no está disponible. | 音声認識は利用できません。 | Spracherkennung ist nicht verfügbar. | La reconnaissance vocale est indisponible. |
| `Open Settings` | Open Settings | 打开设置 | Abrir Ajustes | 設定を開く | Einstellungen öffnen | Ouvrir Réglages |

JSON format — follow the compact style of the App catalog (no spaces around colons). Each entry:

```json
"Processing…": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Processing…" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "处理中…" } },
    "es": { "stringUnit": { "state": "translated", "value": "Procesando…" } },
    "ja": { "stringUnit": { "state": "translated", "value": "処理中…" } },
    "de": { "stringUnit": { "state": "translated", "value": "Verarbeitung…" } },
    "fr": { "stringUnit": { "state": "translated", "value": "Traitement en cours…" } }
  }
}
```

Note: `"Processing"` (a11y label) and `"Processing…"` (display text) are distinct keys because they carry different semantic values (one is an accessibility label, the other a visual progress indicator).

#### 2. App catalog — new a11y label entry
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (add 1 new key)

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Skipped %lld times — tap to manage` | `Skipped %lld times — tap to manage` | `已跳过 %lld 次 — 轻点管理` | `Omitido %lld veces — toca para gestionar` | `%lld 回スキップ — タップして管理` | `%lld Mal übersprungen — zum Verwalten tippen` | `Ignoré %lld fois — touchez pour gérer` |

Note: This is an a11y-only format string (not a plural key — the count is always a simple integer injection). The `%lld` format specifier matches Swift's `String(format:)` convention for accessibility labels. The key uses `%lld` not `%d` to match the production code's existing pattern.

#### 3. App catalog — new macOS menu entries
**File**: `SingleThread/Resources/Localizable.xcstrings`
**Action**: modify (add 3 new keys)

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `About SingleThread` | About SingleThread | 关于 SingleThread | Acerca de SingleThread | SingleThread について | Über SingleThread | À propos de SingleThread |
| `Quit SingleThread` | Quit SingleThread | 退出 SingleThread | Salir de SingleThread | SingleThread を終了 | SingleThread beenden | Quitter SingleThread |
| `Open SingleThread` | Open SingleThread | 打开 SingleThread | Abrir SingleThread | SingleThread を開く | SingleThread öffnen | Ouvrir SingleThread |

`SingleThread` stays English (brand name) embedded in translated surrounding text.

#### 4. Watch catalog — new reschedule entries
**File**: `SingleThreadWatch/Resources/Localizable.xcstrings`
**Action**: modify (add 3 new keys)

| Key | en | zh-Hans | es | ja | de | fr |
|---|---|---|---|---|---|---|
| `Reschedule` | Reschedule | 重新安排 | Reprogramar | 再スケジュール | Neu planen | Replanifier |
| `Reschedule to` | Reschedule to | 重新安排到 | Reprogramar para | 再スケジュール: | Neu planen auf | Replanifier pour |
| `Cancel` | Cancel | 取消 | Cancelar | キャンセル | Abbrechen | Annuler |

Watch catalog uses spaces-around-colons style (`"key" : { ... }`). Match the existing format exactly. Use existing `Cancel` translations from App catalog (zh-Hans: 取消, es: Cancelar, ja: キャンセル, de: Abbrechen, fr: Annuler).

### Verification

#### Automated
- [ ] `SIM='platform=iOS Simulator,name=iPhone 17,OS=latest' xcodebuild -scheme SingleThread -destination "$SIM" test -only-testing:SingleThreadTests/LocalizationTests/nonEnglishValuesDifferFromEnglish` — 0 failures (new entries all have non-English values differing from English source)
- [ ] `make build` succeeds (new catalog entries compile into app binary)
- [ ] `make watch-build` succeeds (new Watch catalog entries compile)

#### Manual
- [ ] Verify new catalog entries appear in Xcode's String Catalog editor with all 6 locales populated and marked "translated"

---

## Phase5: Hardcoded String Remediation — Call Sites

### Changes

#### 1. iOS dictation block
**File**: `SingleThread/ContentView.swift`
**Action**: modify (lines 663, 667, 687, 692)

```swift
// :663 — Before:
Text("Processing…")
// :663 — After:
Text("Processing…")  // SwiftUI auto-lookup — same literal, now backed by catalog

// :667 — Before:
.accessibilityLabel("Processing")
// :667 — After:
.accessibilityLabel(String(localized: "Processing", table: "Localizable", bundle: .main))

// :687 — Before:
Text("Speech recognition is unavailable.")
// :687 — After:
Text("Speech recognition is unavailable.")  // SwiftUI auto-lookup

// :692 — Before:
Button("Open Settings") {
// :692 — After:
Button(String(localized: "Open Settings", table: "Localizable", bundle: .main)) {
```

The `Text` literals already match the catalog keys — SwiftUI's `LocalizedStringKey` auto-lookup will resolve them once the catalog entries exist. For non-`Text` views (`accessibilityLabel`, `Button` title), use `String(localized:)` explicitly.

#### 2. iOS a11y label — ReminderCardView
**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify (line 169)

Check the surrounding context to determine where `skipCount` comes from:

```swift
// :169 — Before:
.accessibilityLabel("Skipped 6 times — tap to manage")
// :169 — After:
.accessibilityLabel(String(
    format: String(localized: "Skipped %lld times — tap to manage",
                   table: "Localizable", bundle: .main),
    skipCount))
```

The `skipCount` variable must be available in this scope — verify it's accessible from the `.accessibilityLabel` modifier site. If not, hoist the `String(format:)` call to a local variable above the view body.

#### 3. Watch reschedule sheet
**File**: `SingleThreadWatch/WatchReminderView.swift`
**Action**: modify (lines 215, 295, 298, 316)

```swift
// :215 — Before:
Button("Reschedule") {
// :215 — After:
Button("Reschedule") {  // SwiftUI auto-lookup against watch main bundle — same literal, now backed by catalog

// :295 — Before:
"Reschedule to",
// :295 — After:
"Reschedule to",  // SwiftUI auto-lookup

// :298 — Before:
Button("Reschedule") {
// :298 — After:
Button("Reschedule") {  // SwiftUI auto-lookup

// :316 — Before:
Button("Cancel") { viewModel.isShowingRescheduleSheet = false }
// :316 — After:
Button("Cancel") { viewModel.isShowingRescheduleSheet = false }  // SwiftUI auto-lookup
```

All Watch call sites use `Text`/`Button` literals — SwiftUI auto-lookup against the watch main-bundle `Localizable` table. No code changes needed beyond adding the catalog entries (done in Phase 4). Verify the literals match the catalog keys exactly (including trailing space in "Reschedule to").

#### 4. macOS commands — `SingleThreadApp+Commands.swift`
**File**: `SingleThread/SingleThreadApp+Commands.swift`
**Action**: modify (lines 17, 23)

```swift
// :17 — Before:
Button("About SingleThread") {
// :17 — After:
Button(String(localized: "About SingleThread", table: "Localizable", bundle: .main)) {

// :23 — Before:
Button("Quit SingleThread") {
// :23 — After:
Button(String(localized: "Quit SingleThread", table: "Localizable", bundle: .main)) {
```

These are `#if os(macOS)` gated — the `String(localized:)` compiles on iOS (the key exists in the iOS app's catalog); actual macOS localization verification requires on-device testing.

#### 5. macOS menu bar — `MenuBarExtraOptions.swift`
**File**: `SingleThread/MenuBarExtraOptions.swift`
**Action**: modify (line 32)

```swift
// :32 — Before:
Button("Open SingleThread") {
// :32 — After:
Button(String(localized: "Open SingleThread", table: "Localizable", bundle: .main)) {
```

Same macOS-only context as above.

### Verification

#### Automated
- [ ] `make build` succeeds (all catalog keys compile into binary; call-site changes compile)
- [ ] `make watch-build` succeeds
- [ ] `make test` (unit only) — all existing tests pass; no new failures introduced

#### Manual
- [ ] **iOS simulator — English locale**: trigger dictation (if possible) or verify the dictation view shows "Processing…" correctly; verify ReminderCardView a11y label reads "Skipped N times — tap to manage"; verify Open Settings button renders
- [ ] **iOS simulator — Spanish locale** (Scheme → Run → Options → App Language = Spanish): verify dictation error text is Spanish, a11y label interpolates Spanish "Omitido N veces", buttons show Spanish labels
- [ ] **Watch simulator — German locale**: verify reschedule sheet shows "Neu planen", "Neu planen auf", "Abbrechen"
- [ ] **macOS**: verify About/Quit/Open menu items show localized text in non-English locale (requires macOS build — mark for on-device verification if local macOS build not available)

---

## Phase6: Final Gate

### Changes

No file changes. Full CI-identical gate to confirm nothing is broken.

### Verification

#### Automated
- [ ] Run `nohup bash ./scripts/test.sh > /tmp/gate.log 2>&1 &` — wait for completion, check `/tmp/gate.log` for zero failures

The gate runs: format, lint, iOS build, watch build, Periphery, unit tests, iOS UI tests, watch UI tests.

If `testAccessibilityAudit` fails on hit-region checks (local-only, known pre-existing), annotate as pre-existing — not a regression from these changes.

---

## Notes for Implementer

### Catalog JSON formatting
- **App catalog** (`SingleThread/Resources/Localizable.xcstrings`): compact style, no spaces around colons, no top-level `version` field
- **Core catalog** (`SingleThreadCore/.../Localizable.xcstrings`): compact style, no top-level `version` field  
- **Watch catalog** (`SingleThreadWatch/Resources/Localizable.xcstrings`): spaces around colons, top-level `"version" : "1.0"`
- Match each catalog's existing style exactly when adding new keys
- Insert new keys in alphabetical order within the `"strings"` dict (or at the end — consistency within each phase matters more than global order)

### Shared-key call-site migration pattern
- iOS app call sites: `bundle: .main` → `SharedStrings.<accessor>` (resolves through `.module`)
- macOS call sites: `Button("Literal")` → `Button(SharedStrings.<accessor>)`
- Watch call sites: Keep using `Text`/`Buttton` literals (resolve through Watch main bundle; Watch catalog keeps own copies of shared keys)
- Widget call sites: Keep using Widget main-bundle literals

### Exclusion list maintenance
- If any new entry added in Phase 4 triggers the guard (English-identical cognate in some locale), add to `excludedIdentities` with a comment
- Format: `ExclusionEntry(catalog: "<App|Core>", key: "<exact key>")`  
- The key string must match the xcstrings key byte-for-byte, including trailing spaces (`"Version %@ "`)

### macOS-only code paths
- `SingleThreadApp+Commands.swift` and `MenuBarExtraOptions.swift` are `#if os(macOS)` gated
- Their catalog entries compile on iOS (keys in App catalog, call sites in `String(localized:)` compile everywhere)
- macOS runtime verification requires a macOS build — mark as manual verification item
- Shared accessor call sites (`Sharedstrings.completeReminder`) compile on all platforms since the accessor is not `#if` gated

### Periphery dead-code check
- `make periphery` may flag new `LocalizedString+Shared.swift` accessors as unused on iOS-only builds (if only macOS call sites consume them)
- If Periphery fails on new shared accessors consumed only by macOS code, add `// periphery:ignore` comments on those accessors
- Clean `DerivedData/` before running Periphery after branch switches (stale index)