# Research Findings — About Modal

Context: main app target's Settings screen, watch surface, app-identity metadata,
author-attribution rendering, presentation/link primitives, and settings test
coverage. All paths relative to repo root. Branch artifacts under
`.pi/qrspi/alanvardy-var-651-add-an-about-modal/`.

---

## Q1: Settings screen structure & presentation from the main view

### Gear-button → sheet flow (`SingleThread/ContentView.swift`)
- The whole main UI is a `ZStack`; the gear button is a `.topTrailing` overlay over it: `.overlay(alignment: .topTrailing)` at `ContentView.swift:62`, `Button { isShowingSettings = true }` at `:66-67`, `Image(systemName: "gearshape")` at `:69`, styled `.font(.title3).controlPlate().contentShape(Rectangle())` at `:70`, `.accessibilityLabel("Settings")` + `.accessibilityAddTraits(.isButton)` at `:71-72`, padding at `:73-74`.
- Presentation entry state: `@State private var isShowingSettings = false` at `ContentView.swift:187`.
- The presentation container is a **standard `.sheet`** (not `fullScreenCover`): `.sheet(isPresented: $isShowingSettings) {` at `ContentView.swift:100`.
- Sheet content picks the `SettingsView` init per platform with `#if os(iOS)` / `#else`: iOS branch at `ContentView.swift:101-119`, non-iOS at `:120-137`. The iOS branch additionally passes `allowsLandscape:` (`:102`) and `enableActionButtons:` (`:103`); these two bindings exist only on iOS.
- SettingsView gets all its bindings from the sheet call site. Backed `@AppStorage` bounds declared in ContentView: `appearanceMode` `:146`, `textSize` `:149`, `allowsLandscape` (iOS-only) `:151-154`, `showMicrophoneButton` `:157`, `backgroundEnabled` `:160`, `backgroundFadePercent` `:163`, `enableActionButtons` (iOS-only) `:165-168`, `showUndatedReminders` `:171`, `sortOption` `:174`, `showDate` `:177`, `showList` `:180`, `showRecurrence` `:183`, `showAlarms` `:186`.
- State-free presentation: SettingsView owns no state; every row binds to a ContentView `@AppStorage` passed in via init, plus a fresh `SettingsViewModel()` (`ContentView.swift:112` / `:136`).

### SettingsView internal navigation container
- SettingsView wraps its content in its own `NavigationStack` (not gated by `#if`): `NavigationStack {` at `SettingsView.swift:155`. This is what lets the "Excluded Lists" `NavigationLink` push inside the sheet.
- The push target is `ExcludedListsView` via `Section { NavigationLink { ExcludedListsView(...) } label: { Label("Excluded Lists", systemImage: "eye.slash") } }` at `SettingsView.swift:229-237`; the subview has its own `.navigationTitle("Excluded Lists")` at `:34` and footer `Text("Excluded lists are hidden from the reminder list.")` around `:30`.

### Form section structure
- The whole body is `NavigationStack { Form { ... } }` at `SettingsView.swift:155-256`.
- Picker/toggle rows are **siblings directly inside `Form`** (no `Section` wrapper around the toggles group). Row order:
  - `Picker("Appearance", selection: $appearanceMode)` iterating `AppearanceMode.allCases` → `:157-160`.
  - `Picker("Text Size", selection: $textSize)` → `:163-167`.
  - `Picker("Sort By", selection: $sortOption)` → `:169-173`.
  - iOS-only `Toggle("Allow >", allowsLandscape)` with label "Allow landscape" → `:175-182` (`#if os(iOS)`:`175` … `:182`).
  - `Toggle("Show microphone")` → `:184-186`.
  - `Toggle("Background")` → `:187-189`.
  - `Picker("Background Fade", $backgroundFadePercent)` over `BackgroundFade.allValues` → `:190-193`.
  - iOS-only `Toggle("Show action buttons")` → `:194-198` (`#if os(iOS)` `:194` … `:198`).
  - `Toggle("Show undated reminders")` → `:199-201`.
  - `Toggle("Show date")` → `:202`, `onChange` → `showPreferenceChanged()` `:205-209` (`#if os(iOS) || os(macOS)`).
  - `Toggle("Show list")` → `:212-214`.
  - `Toggle("Recurrence indicator")` → `:215`, `onChange` → `showPreferenceChanged()` `:216-220`.
  - `Toggle("Reminder alerts")` → `:221`, `onChange` `showPreferenceChanged()` `:224-228`.
- Only two explicit `Section`s: the "Excluded Lists" one (`:229-237`) and an empty footer `Section {} footer: { ... }` (`:238-247`).

### Footer & toolbar
- Footer attribution `Section {} footer:` at `:238-247` (details in Q3).
- Toolbar: single item `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }` at `SettingsView.swift:250-256`. No `.principal`/`.leading` toolbar entries; `@Environment(\.dismiss)` stored at `:279-280`.
- There is **no navigation title** on the Settings Form itself (only `ExcludedListsView` has one at `:34`).

### `#if os(...)` divergences in SettingsView
- `import WidgetKit` guarded by `#if os(iOS) || os(macOS)` at `:3-5`.
- Two `init`s: iOS (`#if os(iOS)`, `:76-114`) includes params `allowsLandscape: Binding<Bool>` `:80` and `enableActionButtons: Binding<Bool>` `:81` with assignments `:99-100`; macOS `#else` `:115-149` omits both. `#endif` `:150`.
- Body rows: `Toggle` "Allow landscape" `#if os(iOS)` `:175-182`; `Toggle` "Show action buttons" `:194-198` (iOS only).
- `.onChange` notify hooks for showDate/showRecurrence/showAlarms are `#if os(iOS) || os(macOS)` (`:205-228`).
- `@Binding` declarations for `allowsLandscape`/`enableActionButtons` wrapped in `#if os(iOS)` at `:266-269`.
- `#Preview` blocks guarded by `#if os(iOS)` at `:292-335` (iOS sample passes `backgroundPhotographer: "NEOM"`, URL `https://unsplash.com/@neom` at `:302-303`; a `nil` variant at `:323-324`).

### SettingsViewModel
- `@MainActor @Observable final class SettingsViewModel` at `SettingsViewModel.swift` (class defined ~`:26-29`).
- Two thin delegators: `allowsLandscapeChanged(_:)` (iOS-only, `#if os(iOS)`), calls `AppDelegate.applyLock(allowsLandscape:)`; `showPreferenceChanged()` (`#if os(iOS) || os(macOS)`) calls `WidgetCenter.shared.reloadAllTimelines()`. `import WidgetKit` gated `:2-4`.

---

## Q2: Does the watchOS target surface secondary UI / settings?

### WatcheApp entry — single root screen
- `SingleThreadWatchApp.swift:17-22`: a single `WindowGroup { WatchReminderView(viewModel: viewModel.reminderViewModel) }` — no tabs, no navigation, no sheets.
- `WatchAppViewModel` built in `init()` at `:13`.

### Only surface is one reminder card; no settings/menu
- `WatchReminderView.swift:58-71` `body` switches on store authorization: `.notDetermined` → `ProgressView("Requesting access…")`; `.fullAccess` → `reminderContent`; default → static `Text("Enable Reminders access in Settings")` (a plain text, not a surface).
- `reminderContent` (`:74-95`) is a `ZStack` choosing `allDoneState` / `reminderCard` / `noRemindersState` plus refresh `ProgressView` and decorative `completionGlowOverlay`.
- Watch-controls: `actionButtons` (`:88-106`) — icon-only Complete (→ `viewModel.completeCurrentReminder()`) and Skip (→ `store.skipCurrentReminder()`) buttons; `refreshButton` (`:151-155`) `Button("Refresh")`.
- **Delete is only reachable via `.confirmationDialog`** — the watch's only modal/popover. Attached to the card's `ScrollView` via `.onTapGesture` → `viewModel.isShowingRefreshConfirmation = true` (`:169-190`), offering `Button("Refresh")` and `Button("Delete", role: .destructive)`. The dialog is `.confirmationDialog("Reminder", isPresented: $viewModel.isShowingRefreshConfirmation) { ... }` at `WatchReminderView.swift:165` / `:183-190`.
- **No `.sheet`, `.fullScreenCover`, `Menu`, `SettingsView`, or editor anywhere in the watch target** (grep of the target finds only the one `.confirmationDialog`/Menu hit).

### The watch only receives/renders phone-side prefs
- `reminderDetails` (`WatchReminderView.swift:200-229`) conditionally shows rows gated by prefs, but never lets the user change them: due-date gated by `viewModel.showDateState.isEnabled` (`:213-215`), recurrence by `:219-220`, alarms by `:222-223`.
- `ShowDateState.swift:11-29` (and `ShowRecurrenceState.swift`, `ShowAlarmsState.swift`) each `@Observable`, `private(set) var isEnabled`, read the shared `preference` in `init`, `apply(_:)` persists+publishes. No local toggle binds.
- `WatchAppViewModel.swift:75-147` `setupSyncService` wires `store` with `sendsShowDate/sendsShowRecurrence/sendsShowAlarms = false` (`:128-129`) — the watch never pushes these to the phone. Only receive hooks: `onShowUndatedRemindersReceived` `:130-135`, `onSkippedIdentifiersReceived` `:139-142`, `onShowDateReceived` `:143-146`, `onShowRecurrenceReceived` `:147-150`, `onShowAlarmsReceived` `:151-154`, `onSortOptionReceived` `:155-158`, `onExcludedListTitlesReceived` `:163-166`. Watch *pushes* only actions: `store.onSkipSetChanged → service.pushAll()` `:168`, `onCompleteReminder → requestCompleteReminder` `:169-170`, `onDeleteReminder → requestDeleteReminder` `:171-172`.
- `showsUndatedReminders` / `sortOption` restored from `.standard` in `init` (`:39-43`), never edited locally.
- `WatchReminderViewModel.swift:14-71` holds only presentation state: `isRefreshing`, `isShowingRefreshConfirmation`, `completionGlow`, plus `task()`, `completeCurrentReminder()`, `refresh(clearSkipped:)`.

### Feature-surface delta vs. main iOS app
- Watch is a read-mostly, one-card companion: Complete / Skip / Refresh / Delete (via confirm dialog). It cannot create reminders: `createReminder` **returns `false` on watchOS** (`SingleThreadCore/.../ReminderStore.swift:212-214`); watch completion/delete are **local-only** (memory removal + callback relays) at `:146-150` / `:182-184`.
- Main iOS app has the full Settings sheet (Appearance/Text Size/Landscape/Mic/Background/… all editable and pushed), reminder creation, iOS-only action-button cluster + `.contextMenu` (`ContentView.swift:311-312`).
- **The watch target files contain zero `#if os()` guards**; platform gating lives in Core (`ReminderStore.swift:146,182,212`) and in the iOS `ContentView.swift` (`:53`, `:101`, `:151`, `:165`, `:311`, `:385`, `:399`). `SkippedReminderSyncService.swift:4` is declared `#if os(iOS) || os(watchOS)`.

---

## Q3: app identity metadata & author attribution model

### Identity via generated Info.plist (no physical file for app)
- The **iOS app target has no physical `Info.plist`** and **no `INFOPLIST_FILE`**; it uses `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_KEY_*` injections.
- Debug config (`project.pbxproj:737-763`): `CURRENT_PROJECT_VERSION = 1` `:737`; `GENERATE_INFOPLIST_FILE = YES` `:743`; usage-desc keys (`NSMicrophoneUsageDescription` `:744`, `NSRemindersUsageDescription` `:745`, `NSSpeechRecognitionUsageDescription` `:746`); `MARKETING_VERSION = 1.0` `:761`; `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.SingleThread` `:762`; `PRODUCT_NAME = "$(TARGET_NAME)"` `:763`.
- Release config mirror: `CURRENT_PROJECT_VERSION = 1` `:787`, `GENERATE_INFOPLIST_FILE = YES` `:793`, `MARKETING_VERSION = 1.0` `:811`, `PRODUCT_NAME` `:813`.
- Target metadata `SingleThread` APPLICATION at pbxproj ~`:247-252`.
- **App target declares no `INFOPLIST_KEY_CFBundleDisplayName`** — display name is synthesized from `PRODUCT_NAME = $(TARGET_NAME)`. Explicit `CFBundleDisplayName` only on secondary targets (watch app :933/:961; widget :990/:1021).
- Widget target mixes both: `GENERATE_INFOPLIST_FILE = YES` **and** `INFOPLIST_FILE = SingleThreadWidget/Info.plist` (`:989`/`:1020`) + `INFOPLIST_KEY_NSHumanReadableCopyright = ""` (`:991`/`:1022`); that physical plist holds only the `NSExtensionPointIdentifier` keys.
- **No `Bundle`/Info.plist metadata is read anywhere** — repo-wide greps for `Bundle.main`, `object(forInfoDictionaryKey:)`, `CFBundleShortVersionString`, `CFBundleVersion` return no matches in `SingleThread/`, `SingleThreadCore/`, `SingleThreadWidget/`, `SingleThreadWatch/`. Identity/version/display name are build-time-only today.

### Author attribution / credit model
- `BackgroundImageStore` is where credit lives. Payload: `private let endpoint = URL(string: "https://vardy.cc/unsplash")` at `BackgroundImageStore.swift:152`; `struct UnsplashPayload: Decodable` (`:39-49`) with `photographer` ("photographer") and `photographerURL` ("photographer_url").
- Observable attribution state: `private(set) var photographer: String?` `:71`, `private(set) var photographerURL: URL?` `:73`. Set during `refreshIfNeeded(maxAge:)` `:114-115` (sets photographer/URL from payload after persisting a `BackgroundMetadata` sidecar first, then flips `imageData` so image+credit cannot disagree). Restored from the sidecar by `loadStoredImage()` (`:166-190`).
- Non-attribution credit wiring into SettingsView:
```
Section {} footer: {
    if let backgroundPhotographer {
        if let backgroundPhotographerURL {
            Link("Photo by \(backgroundPhotographer) on Unsplash", destination: backgroundPhotographerURL)   // :241-243
        } else {
            Text("Photo by \(backgroundPhotographer) on Unsplash")                                          // :244-? 
        }
    }
}
```
at `SettingsView.swift:238-247` (Link at `:241-243`, Text fallback `:245`). Both string literals hardcode "on Unsplash". The strings are *injected* (not owned by SettingsView): stored `private let backgroundPhotographer/...URL` at `:284-285`; assigned from init params in both inits (`:104-105`, `:139-140`).
- Wiring point — `ContentView.swift:110-111` (iOS) / `:127-128` pass `viewModel.backgroundImage.photographer` and `photographerURL` into the sheet. `BackgroundImageStore` is injected into the content VM (default at `:18` / `:34`); refresh is driven from a `.task` on the view.

---

## Q4: presentation & outbound-link primitives catalog

### `.sheet` — 1 site (the only one in the repo)
- `ContentView.swift:100` — `.sheet(isPresented: $isShowingSettings)` presenting `SettingsView`; bound to `@State isShowingSettings`. Triggered by the gear button (`:66-67`). Sheet content built inline per-platform with `#if os(iOS)`; no `.presentationDetents` / `.interactiveDismissDisabled` / explicit `.accessibility` on the sheet itself.
- This is the only precedent for a new presented surface.

### `Link(` — exactly 1 site
- `SettingsView.swift:241-243` — text-form `Link("Photo by \(photographer) on Unsplash", destination:)`, styled as default `Form`/`Section` footer; **no** `.font`/`.foregroundStyle`/`.accessibilityLabel`/`.accessibilityAddTraits`. Falls back to `Text` when URL is nil (`:245`). URL injected from `backgroundPhotographerURL` (from ContentView `:110`).

### `@Environment(\.openURL)` — declaration + one call
- Declared `@Environment(\.openURL) private var openURL` at `ContentView.swift:189-190`.
- Single call at `ContentView.swift:312-322` inside an iOS long-press `.contextMenu`: `Button { if let url = ReminderDeepLink.url(forReminderIdentifier: ...) { openURL(url) } } label: { Label("View in Reminders", ...) }`, plus a `Button` Delete with `.tint(.red)` (`:314`) calling `viewModel.deleteCurrentReminder()`. `.contextMenu` gated by `#if os(iOS)` (`:312`).

### `confirmationDialog` — 1 site (watch)
- `WatchReminderView.swift:165` — the only `confirmationDialog`, offering Refresh / Delete (`:183-190`). Preceded by `.accessibilityAddTraits(.isButton)` on the tappable `ScrollView` (`:164`).

### `Menu` — none
- No `Menu(` (toolbar/menu picker) exists anywhere. The only "menu" primitive is the long-press `.contextMenu` (`ContentView.swift:312`).
- Other navigating primitive: `NavigationLink` in the Settings `NavigationStack` to `ExcludedListsView` (`SettingsView.swift:229-237`).

### `ControlPlateModifier` — shared icon-control styling helper
- `ControlPlateModifier.swift`: sizes to a 56×56 circle (`plateSize: 56`), solid circular `background(resolvedFill, in: Circle())`, shadow radius 4. Scheme-adaptive: dark → fill `.black` / glyph `.white`; light → fill `Color(white: 0.92)` / glyph `Color(white: 0.15)` (defaults; `fill:`/`glyph:` params override).
- Six call sites verified, all in ContentView, each paired with accessibility:
  - gear (`:69-76`): `.controlPlate()` + `.accessibilityLabel("Settings")` + `.isButton`.
  - completeButton (`:398-409`) `.controlPlate()` + `.accessibilityLabel("Complete reminder")` + `.isButton`.
  - skipButton (`:410-421`) `.controlPlate()` + `.accessibilityLabel("Skip reminder")` + `.isButton`.
  - micButton (`:430-444`) `.controlPlate()` + `.accessibilityLabel("Dictate reminder")` + `.isButton`.
  - recordingIndicator (`:447-453`) `controlPlate(fill: .red, glyph: .white)` + `.symbolEffect(.pulse, ...)` + `.accessibilityLabel("Recording")` (no button trait).
  - creationFeedbackView (`:464-471`) `controlPlate(fill: feedback.backgroundColor, glyph: .white)` + `.accessibilityLabel(feedback.accessibilityLabel)`.
- Companion accessibility helpers elsewhere: `ReminderCardView.swift` `.accessibilityLabel`/`.accessibilityCombined` (`:37`,`:51`,`:67`,`:82`); `BackgroundImageStore.swift:198` `.accessibilityHidden(true)`; watch `WatchReminderView.swift:100-111,164,187` plus `:142` hidden; Core comment `ReminderSkip.swift:39`.

---

## Q5: how settings-related changes are tested

### `SettingsViewTests` — `body` string dump
- `SingleThreadTests/SettingsViewTests.swift:13-33` — single test `settingsViewContainsAllPreferenceRows`: builds a `SettingsView` via `settingsView()` helper (`:15`), then `let bodyDescription = String(describing: view.body)` (`:16`) — stringifies the SwiftUI `View.body` (a `NavigationStack { Form { ... } }`) and asserts each expected row label is a substring (`:31` `#expect(bodyDescription.contains(label))`).
- Comment at `:18-20` notes `Form` row labels appear in the body dump (unlike `.sheet` content).
- Row labels (`:21-29`): `commonLabels` includes "Appearance", "Text Size", "Sort By", "Show microphone", "Background", "Background Fade", "Unsplash", "Show undated reminders", "Show date", "Show list", "Recurrence indicator", "Reminder alerts", "Excluded Lists", "Done". Under `#if os(iOS)` (`:25`) `expectedLabels = commonLabels + ["Allow landscape", "Show action buttons"]`; `#else` just `commonLabels` (guards `:25-29`).
- Helpers: two platform variants of `settingsView()`. `#if os(iOS)` `:39-58` passes `allowsLandscape:` + `enableActionButtons:`; `#else` `:60-78` omits them (guards `:39`/`:60`). Both use `.constant(...)` bindings, `backgroundPhotographer: "NEOM"`, a `sampleURL` static, `availableLists: ["Work","Personal"]`, `sortOption: .constant(.priority)`.

### `SettingsViewModelTests` — smoke tests mirroring the VM's `#if` surface
- `initializesWithoutCrash` (`:7-10`) always.
- `allowsLandscapeChangedDoesNotCrash` (`:14-18`) under `#if os(iOS)` (`:12-20`).
- `showPreferenceChangedDoesNotCrash` (`:24-27`) under `#if os(iOS) || os(macOS)` (`:22-29`).
- Mirrors `SettingsViewModel` methods and guards (real method guards: `allowsLandscapeChanged` `:with #if os(iOS)`, `showPreferenceChanged` `#if os(iOS) || os(macOS)`).

### `--seed '<json>'` seam
- `SingleThreadCore/.../UITestingSeed.swift`:
  - `fromLaunchArguments(_:)` (`:27-38`) — reads the value after a `--seed` argument, `JSONDecoder().decode(SeedPayload.self, ...)`; returns `nil` if absent / no trailing value / malformed. `SeedPayload.init(from:)` (`:100-117`) uses `decodeIfPresent` so missing `calendars`/`excludedLists` don't throw; `materialize()` (`:124-148`) builds `EKReminder`/`EKCalendar` off a fresh `EKEventStore`.
  - `resetPersistedState()` (`:41-48`) clears a fixed `persistedKeys` list (lines `:52-68`: `skippedReminderIdentifiers`, `excludedListTitles`, `showDate`, `showList`, `showRecurrence`, `showAlarms`, `showUndatedReminders`, `sortOption`, `enableActionButtons`, `showMicrophoneButton`, `backgroundEnabled`, `allowsLandscape`, `textSize`, `appearanceMode`) from both `AppGroup.defaults` and `UserDefaults.standard`.
- Flow into store: `SingleThread/AppViewModel.swift:init(arguments:)` (`:21`) → `makeStore(arguments:)` (`:108-160`). If a seed parses, it calls `resetPersistedState()` (`:115`) and builds `InMemoryEventStore(reminders:calendars:defaultCalendar:)` wrapped in `ReminderStore(loadsReminders: true)` (`:113-123`). A separate `--ui-testing` seam (iOS-only `:129-156`) yields a deterministic single-reminder store used by persistence-relaunch tests to avoid real EventKit/TCC (`:135-152`).
- UI-test launch wiring: `launchApp(seedJSON:)` sets `app.launchArguments = ["--seed", seedJSON]` (`SingleThreadUITestsFlows.swift:18-24`); `--ui-testing` variants in `testBackgroundToggleHidesAndPersistsAcrossRelaunch` (`:115`, `:139`).

### Gear-button end-to-end settings flows
- The UI tests target the gear button by its accessibility label: `app.buttons["Settings"]` (matching `ContentView.swift:71` `.accessibilityLabel("Settings")`).
- `testSettingsOpensAndShowsControls` (`SingleThreadUITestsFlows.swift:116-130`): seed a reminder → tap gear → assert Appearance/Text/Type/Sort, `app.swipeUp()`, then "Show date".
- `testBackgroundToggleHidesAndPersistsAcrossRelaunch` (`:137-156`): seed → tap gear → flip `app.quits["Background"]` (default "1") → Done → terminate → relaunch with `--ui-testing` (comment `:143-148`: `--seed` would reset the persisted background) → reopen Settings → assert "0".
- `testShowListTogglePersistsAcrossRelaunch` (`:205-220`): same relaunch pattern with `--ui-testing`, asserts default "0" → "1".
- `flipToggle(_:target:)` helper (`:226-241`): SwiftUI `Form` rows expose a nested toggle; taps the inner control up to 3 times until value matches.
- **No `#if os` guards inside the test files**: platform divergence is real source (ContentView `.sheet` `:`101/120, AppViewModel.makeStore `:128`).

---

## Cross-Cutting Observations
- **Single `.sheet` precedent**: the only presented surface in the entire iOS app is Settings (`ContentView.swift:100`); any new modal must follow it — `@State` bool binding + inline sheet + settings-owned `NavigationStack` + toolbar `Done` via `@Environment(\.dismiss)`.
- **Single outbound-link precedent**: the Unsplash `Link()` in the Settings footer (`SettingsView.swift:241-243`) is the only `Link(`; it carries no styling/accessibility modifiers. Configuration-driven URL (nullable) with a `Text` fallback.
- **Attribution content pattern**: author credit is external data fetched by `BackgroundImageStore` (`https://vardy.cc/unsplash`), surfaced as `photographer: String?` / `photographerURL: URL?` observables, injected down into a leaf view — not hardcoded in the view.
- **App identity is build-time only**: no runtime `Bundle`/Info.plist reads exist, so versioning/display-name content are not currently surfaced anywhere; any such data would be the first read path.
- **A11y convention**: every interactive control pairs `.accessibilityLabel` + `.accessibilityAddTraits(.isButton)`; decorative layers get `.accessibilityHidden(true)`; combined card uses `.accessibilityElement(children: .combine)` (`ReminderCardView.swift:82`).
- **watchOS is presentation-only**: it has no sheet/menu/settings surface — its only modal is a `.confirmationDialog` — and simply mirrors phone-pushed prefs; an "About/version" surface there has no existing precedent.
- **Testing style**: settings rows are unit-tested via `String(describing: view.body)` substring checks; view-model effects are empty smoke tests; end-to-end via `--seed` deterministic store + `app.buttons["Settings"]`.

## Open Areas
- `GENERATE_INFOPLIST_FILE` exact synthesized `CFBundleDisplayName` value for the app target not compiled/verified (inferred from `PRODUCT_NAME = $(TARGET_NAME)`) — not documented elsewhere in repo.
- Whether macOS (`#else`) builds of `ContentView`/`SettingsView` run in CI `${sim}` matrix; agent reports focus on iOS; macOS init path lines `:115-149` verified but not build-tested.
- No spot checks on whether `backgroundPhotographer` is ever `nil` in production beyond the preview variant at `:323-324`; the footer gracefully degrades to `Text`.