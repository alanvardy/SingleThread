# Structure Outline

## Approach

Add a read-only, long-form "Privacy" screen pushed from the Settings `List` as a fifth
`NavigationLink { … } label: { Label("Privacy", systemImage: "hand.raised") }` row, matching
the existing `Form`-container + `Section` prose idiom. It is documentation-only — no data-flow,
persistence, or sync changes — so **there are no schema/store/service/transport layers**. The
horizontal decomposition is instead: disclosure **content** → presentational **view** → **entry
point** → **end-to-end** navigation, each layer proven by tests before the next begins.

## Stage 1: Disclosure Content (bottom layer)

Delivers the privacy copy as typed static data — the single source of truth for what the app
claims about its data handling. Green tests here prove the copy is complete and honest (the
design's top risk is "copy accuracy drift", so the copy is centralized and assertable in
isolation, with no UI involved).

**Files**: `SingleThread/PrivacySettingsContent.swift` (new), `SingleThreadTests/PrivacySettingsContentTests.swift` (new)

**Key changes**:
- `struct PrivacySection: Identifiable, Equatable { let id: String; let title: String; let body: String }` — new type
- `enum PrivacyGuideContent { static let sections: [PrivacySection]; static let closingLine: String }` — new; `sections` carries (a) Reminders, (b) Display & sync preferences, (c) Skipped & excluded lists, (d) Background image; `closingLine` carries (e) the "no analytics/tracking/advertising" line

**Tests**:
- `privacyGuideContentCoversAllDisclosures()` — happy path: every section title/body is non-empty and contains its required disclosure fact (e.g. `vardy.cc/unsplash`, "on your Apple Watch" local sync, "never sent", "iCloud").
- `privacyGuideContentHasNoAnalyticsClaim()` — sad path guard: `closingLine` contains the "no analytics / no tracking / no advertising" claim verbatim (catches accidental weakening of the privacy promise).

**Verify**: `./scripts/test.sh` green for the new content tests (no app target changes yet).

---

## Stage 2: Presentational View

Delivers `PrivacySettingsView` — a pure, stateless `Form` that renders `PrivacyGuideContent`
using the `Section(title) { Text(body) }` pattern, with the closing line as a single footer.
Green tests here prove the screen renders the content as SwiftUI, independent of navigation.

**Files**: `SingleThread/PrivacySettingsView.swift` (new), `SingleThreadTests/SettingsViewTests.swift` (extend)

**Key changes**:
- `struct PrivacySettingsView: View { var body: some View }` — new; no bindings, no view model, no `init` parameters (reads `PrivacyGuideContent` directly).
- `.navigationTitle("Privacy")` — matches the pushed-sub-view convention (`FilterSortSettingsView.swift:59`).
- Body uses `Form { ForEach(PrivacyGuideContent.sections) { Section($0.title) { Text($0.body) } } Section {} footer: { Text(PrivacyGuideContent.closingLine) } }` — no `ScrollView`, no `#if os(iOS)` gating (content builds on iOS + macOS unchanged).

**Tests**:
- `privacySettingsViewContainsExpectedContent` (new, in `SettingsViewTests`) — renders `String(describing: view.body)` and asserts substring membership for each section headline and at least one body substring (e.g. `"Privacy"` title, `"Reminders"`, `"Background"`, the closing-line substring). Mirrors the existing render-to-string pattern (`SettingsViewTests.swift:13-25`).

**Verify**: `./scripts/test.sh` green for the view test; `#Preview` renders the Form acceptably at a large Dynamic Type size (manual check — the existing audit won't cover this screen).

---

## Stage 3: Entry Point

Delivers the root `SettingsView` `NavigationLink` row so the screen is reachable. Green tests
here prove the row is present with the correct label/symbol and doesn't disturb the existing
root-label invariants the tests depend on.

**Files**: `SingleThread/SettingsView.swift` (extend), `SingleThreadTests/SettingsViewTests.swift` (extend)

**Key changes**:
- New `NavigationLink { PrivacySettingsView() } label: { Label("Privacy", systemImage: "hand.raised") }` added to the root `List` (after the `Background` row, `SettingsView.swift:72-80`).
- No changes to `SettingsView`'s `init` — `PrivacySettingsView` takes no parameters, so the existing `SettingsBindings`/`excludedLists` plumbing is untouched.

**Tests**:
- `settingsViewContainsNavigationLinkLabels()` (extend) — add `"Privacy"` to the expected-labels array; asserts the new label renders while existing labels (`"Interface"`, `"Reminder"`, `"Filtering & Sorting"`, `"Background"`, `"Done"`) remain unchanged.
- `symbolAvailability` concern (manual): confirm `hand.raised` exists on the iOS + macOS deployment targets (not a code test).

**Verify**: `./scripts/test.sh` green — confirms the row renders and no existing substring/`contains` invariant regressed.

---

## Stage 4: End-to-End Navigation

Delivers the user-facing flow: tapping "Privacy" from Settings navigates into the screen. Green
tests here prove the real app pushes the screen and the headline is visible.

**Files**: `SingleThreadUITests/SingleThreadUITestsFlows.swift` (extend)

**Key changes**:
- Extend `testSettingsOpensAndShowsControls()` (`SingleThreadUITestsFlows.swift:126`): after the `Filtering & Sorting` assertions, pop back to root (`app.navigationBars.buttons.firstMatch.tap()`), then `app.staticTexts["Privacy"].tap()` and assert a **unique** headline `staticText` (e.g. the `Section` title string, not the bare word "Privacy", to avoid `contains` collisions).

**Tests**:
- `testSettingsOpensAndShowsControls()` (extend) — asserts navigation into Privacy and a unique headline exists; the existing `Interface`/`Reminder`/`Filtering & Sorting`/`Background` assertions still pass unchanged (research Q4 invariant note).

**Verify**: `./scripts/test.sh` green (build + lint + unit + UI tests including the accessibility audit, which is unaffected since it never enters Settings).

---

## Testing Checkpoints

- After Stage 1: content unit tests green (copy is complete and honest) before any view exists.
- After Stage 2: view render test green before the screen is wired into Settings.
- After Stage 3: `settingsViewContainsNavigationLinkLabels` green (new label present, old labels intact).
- After Stage 4: `testSettingsOpensAndShowsControls` green — full `./scripts/test.sh` passes.
