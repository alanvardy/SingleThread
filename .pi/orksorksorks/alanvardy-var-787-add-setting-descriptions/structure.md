# Structure Outline — Add setting descriptions

## Approach

Add a static caption under every root navigation row and every control row in the
iOS/macOS Settings UI. Captions are `Text("…")` literals localized via the App
catalog in all six languages, rendered by one shared caption primitive
(`.font(.caption)` + `.foregroundStyle(.secondary)`). Zero state, zero persistence,
zero catalog/key changes outside the App target (design.md Decisions 1–6).

Bottom-up: authored copy + catalog keys → the caption primitive → applying it to
every screen → full gate + visual/a11y/translation review. Each layer ships its
tests green before the next starts.

---

## Stage 1: Catalog & copy (foundation)

Author the canonical caption copy (final wording lands in plan.md; ~30–35 strings)
and register every key in the **App** catalog
(`SingleThread/Resources/Localizable.xcstrings`), `extractionState = "manual"`,
`state = "translated"` in en / zh-Hans / es / ja / de / fr.

What green proves: every caption is non-empty in all six languages, needs no plural
variations, and no existing key was disturbed.

**Files**: `SingleThread/Resources/Localizable.xcstrings` (+~30–35 keys).

**Key changes**:
- ~30–35 new static `String` keys (one per caption/subtitle). No `variations.plural`
  — all captions are static sentences (Decisions D2/D4).

**Tests** (no Swift changes yet, so the existing localization gate is the proof):
- `LocalizationTests.catalogsParseAndHaveNonEmptyEnglish`
- `LocalizationTests.catalogsHaveAllSixLanguages` — fails the moment a caption key
  is added without all six translations.

**Verify**: `make build && make lint`, then
`xcodebuild -only-testing:SingleThreadTests/LocalizationTests -destination "$SIM"` (pinned).

---

## Stage 2: Caption primitive

Factor the uniform caption mechanism into a shared view plus an optional root-row
label helper, so the styling and the VoiceOver-combine mitigation each live in one
place (the "one uniform pattern" from Decision 1).

**Files**: `SingleThread/SettingsCaption.swift` (new).

**Key changes**:
- `struct SettingsCaption: View { let text: LocalizedStringKey }`
  → `Text(text).font(.caption).foregroundStyle(.secondary)`. Call sites pass a
  string literal, so Style A auto-localization is preserved.
- `struct SettingsLinkLabel: View { let title: LocalizedStringKey; let systemImage: String; let caption: LocalizedStringKey }`
  → `Label { VStack(alignment: .leading) { Text(title); SettingsCaption(text: caption) }.accessibilityElement(children: .combine) } icon: { Image(systemName:) }`
- Control-row usage (Toggle/Picker): caption is the second line of the control's
  label closure — `Text(title)` over `SettingsCaption(text:)`, with `.combine` on
  that label `VStack`. No new accessibility identifiers.

**Tests** (Swift Testing, `SingleThreadTests/SettingsCaptionTests.swift`, new):
- happy: `String(describing:)` of `SettingsLinkLabel` body contains both title and caption.
- sad: caption text ≠ title text (no label/caption collision); caption absent when
  `text` renders empty.

**Verify**: `make lint` + `xcodebuild -only-testing:SingleThreadTests/SettingsCaptionTests -destination "$SIM"` + `make build`.

---

## Stage 3: Apply captions to every screen

Wire the primitive into all 8 root rows and every control row; captions inherit the
row's existing `#if os()` gating. No new identifiers, no renames.

**Files**: `SingleThread/SettingsView.swift`, `InterfaceSettingsView.swift`,
`NotificationsSettingsView.swift`, `ReminderSettingsView.swift`,
`FilterSortSettingsView.swift`, `BackgroundSettingsView.swift`.

**Key changes** (all `NavigationLink label:` / Toggle / Picker label closures):
- Root rows → `SettingsLinkLabel(title:systemImage:caption:)` for Interface,
  Notifications (`#if os(iOS)`), Reminder, Filtering & Sorting, Background,
  Purchase, Privacy Policy, About (8).
- Interface: Appearance, Text Size, Allow landscape (iOS), Show microphone,
  Show action buttons (iOS), Show swipe prompt (iOS), Show undo button (iOS).
- Notifications: Enable reminder notifications, Remind after.
- Reminder: Show date, Show list, Recurrence indicator, Reminder alerts, Completion glow.
- Filtering & Sorting: Sort By, Show undated reminders, Excluded Lists link.
- Background: Background, Background Fade, Pin wallpaper, Refresh wallpaper.
- **No caption** under `ExcludedListsView` per-list toggles, nor in Privacy/About/
  Purchase *content* prose (only their root-row subtitles) — Decision 3.

**Tests** (extend `SingleThreadTests/SettingsViewTests.swift`):
- `settingsViewContainsNavigationLinkLabels` → add 8 root-row subtitle assertions.
- `interfaceSettingsViewContainsExpectedRows` → add captions under its existing `#if os(iOS)`.
- NEW `notificationsSettingsViewContainsExpectedRows` → title + 2 captions; adds a
  CI-covered unit test for a screen whose UI *classes* don't run in CI (design risk note).
- `reminderSettingsViewContainsExpectedRows` / `filterSortSettingsViewContainsExpectedRows` /
  `backgroundSettingsViewContainsExpectedRows` (seeded) → add captions.
- Sad/isolation: a Reminder caption does NOT appear in Interface's body; every
  existing asserted label remains byte-identical.

**Verify**: `make build && make lint` +
`xcodebuild -only-testing:SingleThreadTests/SettingsViewTests -destination "$SIM"`.
Optional UI smoke:
`-only-testing:SingleThreadUITests/SingleThreadUITestsFlows/testSettingsOpensAndShowsControls` (unchanged).

---

## Stage 4: Full gate + visual/a11y/translation review

Run the single CI-identical gate and confirm macOS rendering; skim non-English copy.

**Files**: none (verification only).

**Verify**:
- `./scripts/test.sh` — once, full (format / lint / build / Periphery / unit + UI + watch + mac tests).
- `make mac-build` + `make mac-run` — captions don't clip at large `.dynamicType`
  on the macOS two-line List/Form rows (design Open Risk).
- Skim zh-Hans / es / ja / de / fr caption translations before merge.

---

## Testing Checkpoints

- **After Stage 1**: `LocalizationTests` green — all caption keys non-empty in six languages.
- **After Stage 2**: `SettingsCaptionTests` + lint/build green before any screen uses the primitive.
- **After Stage 3**: `SettingsViewTests` (incl. new notifications screen) green; existing settings UI flows unchanged.
- **After Stage 4**: full `./scripts/test.sh` green once; `make mac-build` renders without clipping.

## Non-horizontal notes

- **Two insertion shapes** (NavigationLink label vs. control label closure): the
  design's "one uniform pattern" spans two SwiftUI call sites. The shared
  `SettingsCaption` + `SettingsLinkLabel` factor each shape into the Stage 2
  primitive rather than duplicating styling per screen.
- **Mac & VoiceOver behavior** (clipping at large dynamic type, caption verbosity
  doubling announcements) only becomes observable once the UI is assembled, so they
  are checked at Stage 4. The verifiable part — the `.accessibilityElement(children: .combine)`
  mitigation — is placed in Stage 2 so it lives in the already-proven layer.