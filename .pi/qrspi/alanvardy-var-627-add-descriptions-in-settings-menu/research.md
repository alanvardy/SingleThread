# Research Findings

**Branch:** `alanvardy-var-627-add-descriptions-in-settings-menu`
**Scope:** Settings surface (`SingleThread/SettingsView.swift`), SwiftUI SDK primitives, preference consumption, tests/previews/accessibility, and cross-platform presentation.

---

## Q1: How are the settings rows currently declared in `SettingsView`?

### Findings

- `SettingsView.body` is a `NavigationStack { Form { … } }` (`SingleThread/SettingsView.swift:110-111`) with a `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }` (`:167-172`) and `.modifier(TextSizeModifier(textSize: textSize))` (`:175`). It owns no state — every row binds back to `@AppStorage` values in `ContentView` (`ContentView.swift:184-209`).
- **Row 1 — Appearance Picker** (`:112-117`): `Picker("Appearance", selection: $appearanceMode)` with `ForEach(AppearanceMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.systemImage).tag(mode) }`. `title`/`systemImage` source from `AppearanceMode.title` (`AppearanceMode.swift:55-63`: System/Light/Dark) and `AppearanceMode.systemImage` (`:46-52`: circle.lefthalf.filled/sun.max.fill/moon.fill).
- **Row 2 — Text Size Picker** (`:118-123`): `Picker("Text Size", selection: $textSize)`; same `.tag(size)` pattern; source `TextSize.title` (`TextSize.swift:40-45`) and `TextSize.systemImage` (`:29-36`).
- **Row 3 — Sort By Picker** (`:124-129`): `Picker("Sort By", selection: $sortOption)`; source `SortOption.title` (`SortOption+Presentation.swift:10-14`) and `.systemImage` (`:19-23`) — a SwiftUI-side extension, *not* on Core (`SortOption.swift:6-12` carries only raw cases; see Q3).
- **Row 4 — Allow Landscape Toggle, iOS-only** (`:130-137`): inside `#if os(iOS)` `Toggle(isOn: $allowsLandscape) { Label("Allow Landscape", systemImage: "rectangle.landscape.rotate") }` + `.onChange(of: allowsLandscape) → AppDelegate.applyLock(allowsLandscape: newValue)`.
- **Row 5 — Show Microphone Toggle** (`:138-140`): `Toggle(isOn: $showMicrophoneButton) { Label("Show Microphone", systemImage: "microphone") }` — no local `.onChange`.
- **Row 6 — Enable action buttons Toggle, iOS-only** (`:141-145`): `#if os(iOS)` `Toggle(isOn: $enableActionButtons) { Label("Enable action buttons", systemImage: "hand.tap") }`.
- **Row 7 — Show Undated Toggle** (`:146-148`): `Toggle(isOn: $showUndatedReminders) { Label("Show Undated", systemImage: "calendar.badge.minus") }`.
- **Row 8 — Show Date Toggle** (`:149-156`): `Toggle(isOn: $showDate) { Label("Show Date", systemImage: "calendar") }` + `.onChange(of: showDate)` guarded `#if os(iOS) || os(macOS)` (`:152`) → `WidgetCenter.shared.reloadAllTimelines()` (`:154`).
- **Row 9 — Excluded Projects NavigationLink → submenu** (`:157-166`): `Section { NavigationLink { ExcludedProjectsView(excludedProjects: $excludedProjects, availableProjects: availableProjects) } label: { Label("Excluded Projects", systemImage: "eye.slash") } }`.
- **`ExcludedProjectsView` submenu** (`:12-51`): `Form { Section { ForEach(availableProjects, id: \.self) { project in Toggle(isOn: excludedBinding(for: project)) { Text(project) } } } footer: { Text("Excluded projects are hidden from the reminder list.") } }.navigationTitle("Excluded Projects")`. `excludedBinding(for:)` (`:44-51`) returns `Binding(get: { excludedProjects.contains(project) }, set: insert/remove)` over the `@Binding excludedProjects: Set<String>`.
- **Two init overloads split by platform**:
  - `#if os(iOS)` (`:63`, `:86` `#else`, `:105` `#endif`) — **10 params** adding `allowsLandscape` and `enableActionButtons` (`:65-78`).
  - `#else` — **8 params** (drops `allowsLandscape` + `enableActionButtons`; `:86-93`).
- **Private `@Binding` fields** (`:170-184`) are likewise `#if os(iOS)`-split: `allowsLandscape` + `enableActionButtons` only behind iOS at `:183-185`.

**Pattern:** Picker rows source `title`/`systemImage` from SwiftUI-aware `CaseIterable` enums; toggle rows use *literal* `Label("…", systemImage:)` strings. iOS-only rows are gated inline with `#if os(iOS)`; the platforms split exactly along `allowsLandscape`/`enableActionButtons`.

---

## Q2: SwiftUI SDK affordances for trailing rows and transient anchored popups

### Findings

Interface files (line numbers from the iOS arm64e swiftinterface; representative): `.../Platforms/iPhoneOS.platform/.../SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-ios.swiftinterface`, with macOS (`MacOSX.platform/.../arm64e-apple-macos.swiftinterface`), tvOS, watchOS siblings. watchOS swiftinterface path is irregular (`SwiftUI.swiftmodule/` — no `SwiftUI.framework/Modules` prefix).

- **`popover` — transient anchored popup (iOS/macOS only).** `PopoverAttachmentAnchor` enum (`iOS:11585`, `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)`) with cases `.rect(anchor)` and `.point(UnitPoint)`. Two forms:
  - `popover(item: Binding<Item?>, attachmentAnchor: .rect(.bounds), arrowEdge: Edge? = nil, content:)` — irite `.popover` bound to an identifiable row (`iOS:11596`; `@available(iOS 13.0, macOS 10.15)`; tvOS/watchOS unavailable).
  - `popover(isPresented: Binding<Bool>, attachmentAnchor: .rect(.bounds), arrowEdge:, content:)` — boolean-driven (`iOS:11637`/`macOS:12044`).
  - `popoverCore(...isDetachable:, arrowEdges:)` (`iOS:11683`, `@available(iOS 18.1, macOS 15.1)`). `PopoverContext` does **not** exist in either interface.
- **`sheet` — transient full-width anchored sheet** (`iOS:7145`/`7147`): `sheet(item:…, onDismiss:)` and `sheet(isPresented:…, onDismiss:, content:)`. `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0)`. This is exactly what `ContentView` uses today (`ContentView.swift:104`). No `Sheet` struct type exists.
- **`alert` / `confirmationDialog` — transient modal.** Legacy `struct Alert` (`iOS:1026`, deprecated) with `init(title:message:dismissButton:)` and `init(title:message:primaryButton:secondaryButton:)`. Modern `View.alert(_:isPresented:actions:)` (`macOS:10504-10572`, `iOS:15.0+/macOS:12.0+`) and `View.confirmationDialog` (`iOS:16573-16626`, `@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0)`), with `titleVisibility: .automatic`.
- **`ActionSheet`** (`iOS:637`, deprecated) — macOS unavailable; `typealias Button = SwiftUI.Alert.Button`. Deprecation routes to `confirmationDialog`.
- **`Menu<Label,Content>`** (`iOS:6792`, `@available(iOS 14.0, macOS 11.0, tvOS 17.0)`) — `init(content:onAction:label:)`, `init(_ titleKey, content:)`; **watchOS unavailable**. `MenuButton` (macOS-only, deprecated). `View.contextMenu(menuItems:)` (`iOS:9401`, `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0)`).
- **`Field` / `TextArea` / `SecureField`**: No `TextArea` type. `TextField<Label>` (`iOS:146`) with `init(_ titleKey, text: Binding<String>, axis:)` (`iOS:5071+`, `@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0)`); `SecureField` (same availability); multi-line is `TextEditor`.
- **`Picker`** (`iOS:23359`, `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0)`) — `init(selection:content:label:)` (`iOS:538`), labeled forms. Source `Picker` overloads include `.selection` + object-type enum boundaries.
- **`Label`** (`iOS:193`, `@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0)`) — `init(title:icon:)`; `labelReservedIconWidth`/`labelIconToTitleSpacing`. **`.labelStyle(.iconOnly)` dictates row accessory.**
- **`Section`** (`iOS:107`, `@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0)`) — `Section(content:header:footer:)` and `Section(content:footer:)` — a row-group container, already used with `Section` + `footer:` in `SettingsView.swift:31`.
- **info/help affordance.** `View.help(_ textKey/Text)` (`iOS ~1707`, `@available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0)`) + Resource overload (`iOS 16.0/macOS 13.0`). macOS-only `HelpLink` struct (`macOS:23984`, `@available(macOS 14.0)`). No type named `HelpButton`/`InfoButton`.
- **`Text`** (SwiftUICore) `init(verbatim content:)`; `@_disfavoredOverload init<S>(_ content: S)`. Convenience furniture inits exist via extension macros (`@_alwaysEmitIntoClient`).

**Concrete SDK affordances for “supplementary/trailing to a row” + “transient anchored popup”:**
- (a) Trailing row element: `Section(content:header:footer:)`, `Menu<Label,Content>` trailing-menu, `TextField dena SecureField` row label, `range` `valueLabel`, `TextField` `axis` — I.e. the trailing accessory sits inside the label/row, not as a separate popup.
- (b) Transient anchored popup: `popover(isPresented:attachmentAnchor:arrowEdge:)` / `popover(item:)`, plus `sheet(...)`, `alert/isPresented`, `confirmationDialog`, `ActionSheet`, all with `.attachmentAnchor`/`isPresented`/`onDismiss`. Only popover + sheet reach content with an anchor/edge tie to the control.

** - `popover` and `sheet` are the SDK primitives that both attach a transient content overlay to a row/control AND auto-dismiss; both are iOS+macOS, `popover` is tvOS/watchOS-unavailable while `sheet` is available on all four. macOS `HelpLink` (macOS 14+) is the closest info popup affordance; iOS uses `View.help(...)` label.

---

## Q3 — Where each row’s label lives + localization convention

### Findings
- **All settings copy is hardcoded plain-English Swift string literals.** Grep found **no** `LocalizedStringKey`, `StringResource`, `StringCatalog`, or `NSLocalizedString` in the app target. No localization key framework exists for settings (or the surfaces generally).
- The only localization-adjacent types in the repo are unrelated to settings: `LocalizedStringResource` for the *widget* Intents (`SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift:14,37` — “Complete Reminder”/“Skip Reminder”, not the settings menu), and `error.localizedDescription` runtime (e.g. `ContentView.swift:536`).
- **Picker row titles are driven by enums** (not literals in `SettingsView`):
  - `AppearanceMode.title` (`AppearanceMode.swift:55-63`: System/Light/Dark) and `.systemImage` (`:46-52`).
  - `TextSize.title` (`TextSize.swift:40-45`: System/Small/Medium/Large/Extra Large) and `.systemImage` (`:29-36`).
  - `SortOption.title` (`SingleThread/SortOption+Presentation.swift:10-14`: Priority/Due Date/Title) and `.systemImage` (`:19-23`: exclamationmark.3/calendar/textformat.abc). **This presentation extension lives in the app target, not in Core** (`SortOption+Presentation.swift:5-8` documents “Core stays SwiftUI-free; the app target owns `title`/`systemImage`”). Core `SortOption.swift:71-80` carries only the three raw cases + `defaultsKey`.
- **Toggle-row labels are literal inline strings** in `SettingsView`, each with its own SF Symbol:
  - “Allow Landscape” (`:132`), “Show Microphone” (`:139`), “Enable action buttons” (`:143`), “Show Undated” (`:147`), “Show Date” (`:150`), “Excluded Projects” (`:163`), and the toolbar `Button("Done")` (`:169`).
- **`ExcludedProjectsView` footer + title:** `Text("Excluded projects are hidden from the reminder list.")` (`:31`) and `.navigationTitle("Excluded Projects")` (`:34`).
- **ContentView copy convention** (all literals): gear `.accessibilityLabel("Settings")` (`ContentView.swift:80`); empty-state copy `emptyStateCopy(hasHidden:)` (`:131-141`) and `allDoneStateCopy()` (`:145-149`); auth-denied `Text("Enable access in Settings to see your reminders.")` (`:290`); accessibility labels `"Complete reminder"`/`"Skip reminder"`/`"Delete reminder"`/`"Dictate reminder"`/`"Recording"` (`:250,262,436,476,488`).
- **SF Symbol naming**: `systemImage` strings are **dotted-lowercase SF Symbol identifiers** — multi-word names joined by periods with component suffixes, e.g. `"rectangle.landscape.rotate"`, `"calendar.badge.minus"`, `"textformat.size.larger"`, `"exclamationmark.3"`, `"eye.slash"`, `"hand.tap"`.
- The only unit test asserting these rows pins the exact English literals (`SingleThreadTests/SettingsViewTests.swift:32-49`, `.contains("Appearance")…`), so any copy change would require updating that assertion (Q5).

**No localization is present for settings; all copy is inline English string litter with per-slot systemImage SF Symbol identifiers. The enum-driven pickers centralize the row title; the toggles keep literal `Label`+`systemImage` inline.**

---

## Q4 — What each preference actually does at its consumption site

### Findings
- **`allowsLandscape`** (iOS-only):
  - Binding `@AppStorage("allowsLandscape")` (`ContentView.swift:191`). Passed to `SettingsView` (`ContentView.swift:109`), rendered as iOS Toggle (`SettingsView.swift:130-137`), `.onChange` → `AppDelegate.applyLock(allowsLandscape: newValue)` (`SettingsView.swift:135`).
  - `AppDelegate.applyLock` (`SingleThread/AppDelegate.swift:31-42`): builds `UIInterfaceOrientationMask` = `.allButUpsideDown` (true) vs `.portrait` (false); calls `setNeedsUpdateOfSupportedInterfaceOrientations()` + `requestGeometryUpdate(.iOS(interfaceOrientations: mask))`.
  - Launch read: `application(supportedInterfaceOrientationsFor:)` (`AppDelegate.swift:51-57`) reads `UserDefaults.standard[“allowsLandscape”]` directly (default `true`), returns `.allButUpsideDown`/`.portrait`.
  - Behavior: OFF forces portrait (launch + immediate rotation request); ON allows all-but-upside-down. Fully implemented (not hollow).
- **`enableActionButtons`** (iOS-only):
  - `@AppStorage("enableActionButtons")` (`ContentView.swift:199`). Toggle `SettingsView.swift:142-144`. Consumer: `showsActionButtons` (`ContentView.swift:56-58`) = `enableActionButtons && store.visibleReminders.first != nil`; used in `bottomBar` (`ContentView.swift:410-414`) to render `actionCluster` (complete + mic + skip, `:454-459`) vs `micButton`. Behavior: ON + a visible reminder replaces the plain dictation mic with the Complete/Skip cluster on iOS. Implemented.
- **`showMicrophoneButton`**:
  - `@AppStorage("showMicrophoneButton")` (`ContentView.swift:195`). Consumer gates `bottomBar` (`ContentView.swift:410`): `else if canDictate, showMicrophoneButton { … micButton }`. OFF hides the dictation mic entry. Implemented.
- **`showUndatedReminders`**:
  - `@AppStorage("showUndatedReminders", store: AppGroup.defaults)` (`ContentView.swift:203`). `.task` seeds `store.showsUndatedReminders` (`ContentView.swift:86`); `.onChange` → `store.showsUndatedReminders = newValue` + `store.reload()` (`ContentView.swift:89-90`).
  - In `ReminderStore` (`SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift`): `showsUndatedReminders` `didSet` fires `onShowUndatedRemindersChanged` (`:100-104`); `reload()` (`:251-308`) uses nil/nil date predicate when true (surfaces undated reminders), plus `hasHiddenFor` visibility derivation (`:273-284`). Implemented (widens the fetch + reload).
- **`showDate`**:
  - `@AppStorage("showDate", store: AppGroup.defaults)` (`ContentView.swift:209`); second read `SingleThreadApp.swift:95`. Consumers: (a) card renders due date only when `showDate && dueDateComponents?.date` (`ReminderCardView.swift:33-34`); (b) `SettingsView.swift:152-156` `.onChange` → `WidgetCenter.shared.reloadAllTimelines()` guarded `#if os(iOS) || os(macOS)`. (c) independent iOS hook — `SingleThreadApp.swift:78-84` `.onChange(of: showDate)` → `syncService?.pushShowDate(newValue)`. Implemented; differ from `showsUndated` (a separate binding, `ContentView.swift:203`).
- **`appearanceMode`**:
  - `@AppStorage("appearanceMode")` (`ContentView.swift:184`). `.onChange` (`ContentView.swift:96-101`): iOS `AppDelegate.applyAppearance(newValue)`, macOS `MacAppDelegate.applyAppearance(newValue)`.
  - `AppDelegate.applyAppearance` (`AppDelegate.swift:15-22`): sets `window.overrideUserInterfaceStyle = mode.windowOverrideStyle` (`.system` → `.unspecified` clears). macOS: `window.appearance = mode.appKitAppearance` (`AppDelegate.swift:72-75`). Implemented per-platform.
- **`textSize`**:
  - `@Binding("textSize")` (`ContentView.swift:187`). `.modifier(TextSizeModifier(textSize: textSize))` at both `ContentView.swift:103` and `SettingsView.swift:175`. `TextSizeModifier` (`ContentView.swift:547-553`) applies `content.dynamicTypeSize(size)` only when `textSize.dynamicTypeSize` is non-nil (`.system` → nil, follows system). Implemented.
- **`sortOption`**:
  - `@AppStorage(SortOption.defaultsKey, …)` (`ContentView.swift:206`). `.onChange` → `store.setSortOption(newValue)` (`ContentView.swift:93-94`). `ReminderStore.setSortOption` (`:230-234`) assigns + fires `onSortOptionChanged`/`onRemindersChanged`; ordering applies in `visibleReminders` (`:107-112`) via `ReminderSort.areInIncreasingOrder(…, using: sortOption)` (`ReminderSort.swift:24-54`). Implemented.
- **`excludedProjects`**:
  - `excludedProjectsBinding` (`ContentView.swift:223-227`) = `Binding(get: { store.excludedProjectTitles }, set: { store.setExcludedProjectTitles($0) })`. Submenu `ExcludedProjectsView` toggles per-project membership.
  - Consumer `ReminderStore.setExcludedProjectTitles` (`:311-317`): sets `excludedProjectTitles`, persists via `excludeStore.save` → `ExcludedProjectStore.swift` (UserDefaults key `excludedProjects`), fires hooks. `visibleReminders` filters `.filter { !excludedProjects.contains($0.calendar?.title ?? "") }` (`:107-112`). Re-read in `reload()` at `:301`. Implemented.

**Finish:** Running `make` none. No hollow preferences were found — every iOS/macOS row is consumed. `showDate` is distinct from `showsUndated` (separate bindings). `WidgetCenter` is external (WidgetKit import), its internals not visible here.

---

## Q5 — How the settings window is tested, previewed, accessibility-ruled

### Findings
- **Single unit test `settingsViewContainsAllPreferenceNodes`** (`SingleThreadTests/SettingsViewTests.swift:8-49`). Asserts `String(describing: view.body)` `#expect(bodyDescription.contains("Appearance"|"Text Size"|"Sort By"|"Microphone"|"Show Undated"|"Show Date"|"Excluded Projects"|"Done"))` (`:40-47`) and iOS-only `.contains("Landscape")`/`.contains("Enable action buttons")` (`:49-50`, guarded `#if os(iOS)`). Note: it builds `SettingsView` with `.constant(...)` and splits iOS/`#else` inits — same 10-arg vs 8-arg shape as Q1.
- **`bodyDescription` is derived from `view.body` (the `Form`), not the `.sheet` content.** The test comment states exactly this (`:37-39`). So a new row inside the `SettingsView` form would only appear in the `.contains` assertion if an explicit `#expect(bodyDescription.contains(...))` line is added for its label. There is no generic “assert any new row” — every current row is individually pinned.
- **SwiftLint accessibility rules** (`swiftlint.yml:44-80` opt-in): `.swiftlint.yml:45` `- accessibility_label_for_image` and `:46` `accessibility_trait_for_button` — both **enabled** and inherited by targets except `SingleThreadTests/.swiftlint.yml` (which only relaxes `force_unwrapping`). So a new interactive affordance in `SettingsView.swift` must carry an explicit image/accessibility label + a button trait (`label` + `.accessibilityAddTraits(.isButton)`).
- **UI accessibility audit** (`SingleThreadUITests/SingleThreadUITests.swift`): `testAccessibilityAudit()` (`:17`) launches `--ui-testing` and waits for any static text (`:21-27`). Platform forks:
  - iOS CI (`if env[“CI”]=="true"`): audits `.sufficientElementDescription, .trait` only (`:41-42`); comment (`. 33-39`) explains `.dynamicType`/`.hitRegion` are skipped on CI (hang risk).
  - iOS local (`:46`): full `[.dynamicType, .hitRegion, .sufficientElementDescription, .trait]`.
  - macOS (`#else`, `:51`): default `app.performAccessibilityAudit()`.
- **Accessibility attach pattern** in the settings path: gear button `.accessibilityLabel("Settings")` + `.accessibilityAddTraits(.isButton)` (`ContentView.swift:80-81`). Same pattern on every action button (`ContentView.swift:250,262,436,450,476`, etc.).
- **Previews** (`SingleThread/SettingsView.swift:199-244`): iOS has `#Preview("Default")` (`$200`) and `#Preview("Dark + Extra Large")` (`:214`) each supplying all 10 args; `#else` supplies the 8-arg init. Both are pure visual/config — they don’t attach accessibility traits themselves.

**How a new interactive affordance would be verified:** (1) to appear in the unit settings test, a matching `.contains(view.body)` label assertion must be added; (2) SwiftLint `accessibility_label_for_image`/`accessibility_trait_for_button` will force the label + `.isButton` trait at lint time; (3) `testAccessibilityAudit` then exercises the real app for `.trait` (CI) and `.dynamicType`/`.hitRegion` (local iOS) or full defaults (macOS). The two checks are complementary: SwiftLint is static trait/label presence, the unit test asserts render in body description, and the audit runs the live row.

---

## Q6 — On which targets is `SettingsView` presented, and how its presentation differs

### Findings
- **`ContentView` is the only constructor of `SettingsView`**, inside `.sheet(isPresented: $isShowingSettings)` (`ContentView.swift:104`) with a `#if os(iOS) / #else` split for which init it passes (`ContentView.swift:105-117` iOS full arg list incl. `allowsLandscape`/`enableActionButtons`; `:118-131` macOS/else 8-arg, no iOS-only fields).
- **iPhone + iPad** both are `os(iOS)` → iOS variant (with iOS toggles). **macOS** → `#else` variant (no iOS-only rows). The gear button that opens settings is identical across platforms (`ContentView.swift:70-72`).
- **watchOS** does **not compile or present `ContentView`/`SettingsView`** — `SingleThreadWatch/SingleThreadWatchApp.swift` builds `WatchReminderView(store:)` instead; grep finds no `ContentView`/`SettingsView`/`TextSizeModifier` in `SingleThreadWatch/` or `SingleThreadCore/`. So the watch has **no settings sheet**; all watch preferences flow via WatchConnectivity (`SkippedReminderSyncService` push/poll).
- **Presentation difference across iPhone/iPad/macOS** is confined to the sheet’s arg list (`allowsLandscape` + `enableActionButtons` present on iOS only) and the same cent’s bottom-bar divergence (macOS renders a separate `actionButtons` HStack via `#if os(macOS)` at `ContentView.swift:239-270`; iOS renders `actionCluster` under `showsActionButtons`).
- Preview blocks in `SettingsView.swift` also fork on `#if os(iOS)` vs `#else` (iOS two previews, else one), mirroring the init-arg split.

Generated as part of `ContentView`’s `.sheet`; iOS/else split is param-list; watchOS routes entirely around settings; WidgetKit’s `WidgetCenter.reloadAllTimelines()` (iOS/macOS only, `SettingsView.swift:154`) is external.

---

## Cross-Cutting Observations
- **Platform conditioning is pervasive via `#if os(...)`** — every settings row that differs (or not) carries explicit guards: iOS-only rows (`allowsLandscape`, `enableActionButtons`), iOS|macOS-only `WidgetCenter` reload on `showDate`, `#else` for macOS, and the watch target omits `ContentView` entirely.
- **Two parallel init systems** (SettingsView init + ContentView sheet call) must stay in lockstep: both split iOS / non-iOS on the same two `allowsLandscape`/`enableActionButtons` args.
- **SwiftUI presentation props for enums are app-target side** (`SortOption+Presentation.swift`), keeping Core SwiftUI-free — while `AppearanceMode`/`TextSize` are themselves app-target enums that reach into SwiftUI-only types (`UIUserInterfaceStyle`, `DynamicTypeSize`).
- **Settings layer copies are the single source of truth** for `title`/`systemImage` on toggles; the three Pickers source from enums, the six toggles + footer are literal.

---

## Open Areas
- **WidgetCenter internals unresolved** — `WidgetCenter.shared.reloadAllTimelines()` is WidgetKit-external; its exact effect on widget timelines could not be traced in-repo (only its iOS|macOS call site).
- Once `showDate` `.onChange` reload happens at `SettingsView.swift:154` / `SingleThreadApp.swift:64` (external) — duplication of effect across WidgetCenter call sites not fully resolvable from this repo.
- tvOS/watchOS swiftinterface verification was spot-checked, not exhaustively line-printed for every member (residual risk noted by Q2 agent).
- The swiftinterface line numbers are specific to the installed Xcode 26 SDK; they may shift across Xcode releases.