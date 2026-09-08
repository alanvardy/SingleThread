# Design Discussion — Add setting descriptions

## Current State

The Settings UI is a modal `NavigationStack > List` with **two headerless
`Section`s** (`SingleThread/SettingsView.swift:32-34`, second at `:112`),
presented from the gear button (`ContentView.swift:163-165`, sheet `:243-244`).
It pushes **8 root `NavigationLink` rows** — Interface, Notifications, Reminder,
Filtering & Sorting, Background, Purchase, Privacy Policy, About — each rendered
as `Label("…", systemImage:)` with zero explanatory text (`SettingsView.swift:35-126`).

Each root row pushes a sub-screen (`Form`/`List`) of controls, also bare:
- Interface: Appearance/Text Size pickers + iOS-only toggles (`InterfaceSettingsView`)
- Notifications: enable toggle + 24/48/72h picker (`NotificationsSettingsView.swift:13,17`)
- Reminder: 5 show-* toggles (`ReminderSettingsView.swift:23-57`)
- Filtering & Sorting: sort picker, undated toggle, Excluded Lists link (`FilterSortSettingsView.swift:20-30`)
- Background: enabled toggle, fade picker, Pin toggle, refresh button (`BackgroundSettingsView.swift:20-41`)

The only existing explanatory text is **plain default-styled footers** in three
places: `ExcludedListsView.swift:26-27`, the conditional purchase footer
(`PurchaseSettingsView.swift:28-38`), and the interpolated Unsplash credit
(`BackgroundSettingsView.swift:55-61`). Research found **no `.font`, no
`.foregroundStyle(.secondary)`, no `.headerProminence`** anywhere in settings
chrome — captions have no styling precedent to copy.

Settings state flows through a single `SettingsBindings` bag → `.onChange`
write-back → `ContentView`'s 19 `@AppStorage` keys (`ContentView+Settings.swift:14-44`,
`ContentView.swift:72-133`). Captions are static text and **touch none of this**.

## Desired End State

Every root navigation row and every individual control row shows a short caption
under its title:

- **8 root rows** get a subtitle under the `Label` (e.g. Reminder →
  *"Settings that impact how the reminder is displayed"*).
- **Every control row** in Interface, Notifications, Reminder, Filtering &
  Sorting, and Background gets a caption under the control's label (e.g.
  Pin wallpaper → *"Prevents the background from refreshing automatically"*).
- Captions are `Text("…")` literals in the **App catalog** only
  (`SingleThread/Resources/Localizable.xcstrings`), translated in all six
  languages (en, zh-Hans, es, ja, de, fr), static — no interpolation.
- Persistence, widget reload, and watch sync are untouched: no new
  `@AppStorage` keys, no `SettingsBindings`/`makeSettingsBag`/`.onChange` edits.

**Verification of correct:**
- `make build` + `make lint` clean (warnings-as-errors).
- `SettingsViewTests` extended to assert caption substrings; still green.
- `LocalizationTests.catalogsHaveAllSixLanguages` / `catalogsParseAndHaveNonEmptyEnglish`
  pass (auto-covers the new keys once translated).
- Existing UI tests pass **unchanged** (we only add text; no asserted string is
  renamed, reordered, or removed).
- Full `./scripts/test.sh` runs once at the end (conventions.md).

## Patterns to Follow

- **Style A literals** — captions are SwiftUI `Text("…")` literals auto-localized
  against the App main-bundle catalog, matching every existing row label
  (`SettingsView.swift:54,63,76,86,96,116,122`). No explicit
  `String(localized:table:bundle:)` unless a `String` value is needed (which it isn't here).
- **Row-tagging precedent** — `.accessibilityIdentifier` per control
  (`settingsInterfaceRow` etc., `SettingsView.swift:56,65,78,88,98,108,118,125`)
  is how tests address rows; captions ride inside existing rows and never need
  new identifiers.
- **Tone precedent** — the existing footers are short, neutral, second-person-free
  ("Excluded lists are hidden from the reminder list.", `ExcludedListsView.swift:26-27`).
  Captions follow the same voice.
- **Platform gating inheritance** — captions live inside the parent row and
  inherit its existing `#if os(iOS)` gating (Notifications row `SettingsView.swift:57-66`;
  iOS-only Interface toggles `InterfaceSettingsView.swift:49-57,62-75`). No new gating.
- **If a number ever needs interpolating** (not in this task), the repo pattern is
  `String(localized:table:bundle:)` interpolation with `%lld` plural keys
  (`ReminderRecurrenceFormatter.swift:16-19`).

**Patterns NOT to follow:**
- The unlocalized `@State` error strings in `PurchaseSettingsView.swift:163-165`
  ("Product not available.") are an existing anti-pattern; captions must **not**
  bypass the catalog.
- Do **not** add `@AppStorage`/`SettingsBindings`/`.onChange` wiring — captions
  are pure text, zero state.
- Do **not** add wall-clock-number plural keys just to honor the task's literal
  "every X hours" example (see Decision D2 — the honest caption is static).

## Design Decisions

1. **Caption mechanism**: A `VStack(alignment: .leading)` inside each row's label
   container — title on top, caption below in `.font(.caption)` +
   `.foregroundStyle(.secondary)`. For root links the `Label` becomes an
   `HStack { Label(title, systemImage:); Spacer() }`-adjacent structure whose label
   text is the `VStack`; for Toggle/Picker rows the caption goes in the control's
   trailing-label/content closure. One uniform pattern, identical on iOS/macOS.
   *(Option A — per-row, not `Section` header/footer.)*

2. **The "X hours" caption is static and honest**: `defaultMaxAge = 86400` is a
   `private` cache max-age (`BackgroundImageStore.swift:177`), not a user-visible
   rotation cadence — there is no interval picker, only Pin + manual refresh
   (`BackgroundSettingsView.swift:30-35`). Promising "changes every X hours" would
   be false. **Pin wallpaper → "Prevents the background from refreshing automatically."**
   No constant is exposed; no `%lld` plural key; no interpolation. *(Option C.)*
   The literal X-derived wording is recorded as a rejected option in case product
   later adds a real rotation interval.

3. **Scope**: all 8 root links + every control in Interface, Notifications,
   Reminder, Filtering & Sorting, Background, plus the Excluded Lists link's row.
   **Excluded:** content screens' prose (Privacy/About bodies, Purchase copy), and
   per-list dynamic toggles in `ExcludedListsView` (its existing footer already
   describes the whole group; per-list captions would be 30 near-identical strings).
   *(Option A, with the ExcludedLists boundary noted for review.)*

4. **Catalog surface**: App catalog only (`SingleThread/Resources/Localizable.xcstrings`,
   `bundle: .main` via literals), all keys `extractionState = "manual"`,
   `state = "translated"` in all six languages. No Core/Watch/Widget catalog edits;
   no plural variations needed. This is the same surface every other settings string uses.

5. **Testing**: extend `SettingsViewTests` per-screen body-substring assertions
   (`SettingsViewTests.swift:37-181` — `String(describing: view.body)`) to also
   assert each caption's English literal is present, adding one representative
   caption per screen plus a dedicated pass over the root-row subtitles. **No new
   UI test** for caption presence (brittle, low signal); existing UI tests must
   pass unchanged. Six-language non-emptiness is already enforced by
   `LocalizationTests.catalogsHaveAllSixLanguages` (`LocalizationTests.swift:63-85`) —
   the moment a caption key is added untranslated it fails, so no extra localization test.
   *(Option A.)*

6. **Copy is a one-time authored list**, not runtime-derived. Final wording for all
   ~35 captions lands in `plan.md`; representative copy in this doc's examples sets
   the tone. All captions are sentence-case, ≤ 8 words, neutral voice.

## What We're NOT Doing

- **Not adding** any setting, binding, `@AppStorage` key, App Group key, widget
  reload, or watch-sync path. Captions are display-only.
- **Not exposing** `defaultMaxAge` (stays `private`) or any time constant; no
  runtime number interpolation; no new `%lld`/`%@` plural keys.
- **Not adding** `Section header:`/`footer:` captions to the two root List sections
  (they remain headerless; "section" descriptions attach to the navigation rows).
- **Not touching** Privacy/About/Purchase *content* (their prose already reads as
  self-descriptive), only their root-link subtitles.
- **Not adding** captions under `ExcludedListsView` per-list toggles.
- **Not editing** Core/Watch/Widget `.xcstrings` catalogs or InfoPlist.strings.
- **Not renaming/reordering** any existing row label, accessibility identifier, or
  control — every asserted string and id stays byte-identical.

## Open Risks

- **macOS two-line List rows**: the shared files compile for macOS; a `VStack`
  subtitle inside a macOS `List` `NavigationLink` label and inside `Form` control
  labels needs a visual check on the `make mac-build` path. Purely presentational,
  but confirm it doesn't clip at very large text sizes (`.dynamicType` a11y audit
  exists in CI).
- **Accessibility verbosity**: captions double VoiceOver announcements per row.
  Mitigate by keeping captions a distinct `Text` under the title (not duplicating
  the title) and, if needed, `.accessibilityElement(children: .combine)` on the row
  so title+caption read as one element.
- **Copy quality in 6 languages**: captions are machine-aided translations; a human
  (you) should skim zh-Hans/ja/de/fr/es before merge.
- **Body-substring collision**: `SettingsViewTests` asserts substrings, so a caption
  must not — and won't — be an exact duplicate of another asserted row label; captions
  are distinct sentences.
- **Notification captions are CI-invisible**: the three notification UI classes are
  in no CI group (`research.md` Open Areas), so `NotificationsSettingsView` captions
  are only guarded by the local `./scripts/test.sh` whole-target pass.