I have completed the full investigation. All 48 Button call sites across the three targets have been read in context, along with every styling modifier site and the two plate modifiers. Here is the complete findings document.

---

# Q1 — Complete Button Styling Inventory (all targets)

**Scope searched:** `SingleThread/*.swift` (34 Button call sites), `SingleThreadWatch/*.swift` (12, all in `WatchReminderView.swift`), `SingleThreadWidget/*.swift` (2, all in `NextThingWidget.swift`). Supporting files read: `ControlPlateModifier.swift`, `CardPlate.swift`, `CardPlateModifier.swift`, `SingleThreadApp.swift`, `EmptyStateCard.swift`, `AGENTS.md`, plus in-repo prior research under `.pi/qrspi/`.

**Method:** `grep` for `Button(`, `\bButton\b`, `buttonStyle`, `.tint(`, `.labelStyle(`, `.controlSize(`, `.shadow(`, then read every hit in context. Every line reference below is verified against the current working tree.

**Global count facts**
- `.buttonStyle` applied to a `Button`: exactly **7 sites** (`ReminderCardView.swift:153`, `:194`; `PurchaseSettingsView.swift:89`, `:113`, `:191`; `NextThingWidget.swift:154`, `:163`). The 8th `buttonStyle` match (`ContentView.swift:475`) is `.listStyle(.plain)`, not a button.
- `.tint(` on controls: exactly **14 sites** (listed per-button below). Zero on the watch nudge, refresh, dialog, or toolbar buttons.
- `.controlSize(`: **zero matches** anywhere in the three targets.
- Custom `ButtonStyle` structs: **none exist** (see §4). The only `ButtonStyle` string in the repo is a reflected built-in style name in a test (`SingleThreadTests/SwipePromptTests.swift:51`).

---

## 1. SingleThread (iOS + iPadOS + macOS app target) — 34 buttons

### 1.1 Gear / Settings button
- **`ContentView.swift:195`** — `Button { settingsBag = makeSettingsBag(); isShowingSettings = true }`.
  - Label: `Image(systemName: "gearshape")` `.font(.title3)` (`:200`) → `.controlPlate()` (`:201`) → `.contentShape(Rectangle())` (`:202`).
  - Button-level: `.accessibilityLabel("Settings")` (`:204`), id `settingsButton` (`:205`), `.accessibilityAddTraits(.isButton)` (`:206`), padding (`:207–208`).
  - **No `.buttonStyle`.** Platform-default style; chrome drawn manually by `controlPlate` on the label.

### 1.2 macOS-only Refresh button
- **`ContentView.swift:212`** (inside `#if os(macOS)`) — `Button { Task { await viewModel.refreshManual() } }`.
  - Label: `Image(systemName: "arrow.clockwise")` `.font(.title3)` (`:216`) → `.controlPlate()` (`:217`).
  - `.disabled(viewModel.isRefreshing)` (`:219`), a11y label `"Refresh"` (`:220`), id `refreshButton` (`:221`).
  - **No `.buttonStyle`.**

### 1.3 iOS-only Undo button
- **`ContentView.swift:230`** (inside `#if os(iOS)`, gated by `hasUndoableReminder && showUndoButton && canMutate` at `:229`) — `Button { Task { await viewModel.undoLastCompletion() } }`.
  - Label: `Image(systemName: "arrow.uturn.backward")` `.font(.title3)` (`:234`) → `.controlPlate()` (`:235`) → `.contentShape(Rectangle())` (`:236`).
  - a11y `"Undo completion"` (`:238`), id `undoButton` (`:239`).
  - **No `.buttonStyle`.**

### 1.4 iOS context-menu buttons (on the reminder card row)
- **`ContentView.swift:438`** — `Button { viewModel.openInReminders(reminder); … }`, label `Label("View in Reminders", systemImage: "eye")` (`:443`). **Zero styling modifiers.**
- **`ContentView.swift:447`** — `Button { Task { await viewModel.deleteCurrentReminder() } }`, label `Label(SharedStrings.deleteAction, systemImage: "trash")`, `.accessibilityLabel` (`:452`), id `deleteButton` (`:453`), **`.tint(.red)`** (`:454`). In `#if os(iOS) .contextMenu` (`:437`).

### 1.5 iOS swipe-action buttons
- **`ContentView.swift:458`** — leading swipe complete: label `Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")`, **`.tint(.green)`** (`:463`).
- **`ContentView.swift:466`** — trailing swipe skip: label `Label(SharedStrings.skipAction, systemImage: "circle.slash")`, **`.tint(.orange)`** (`:471`).
- Neither has `.buttonStyle`; these are `swipeActions(edge:)` rows (`:457`, `:465`).

### 1.6 iOS bottom-bar Complete (bottom-bar cluster)
- **`ContentView.swift:502`** — `Button { Task { await viewModel.completeCurrentReminder() } }` (inside `#if os(iOS)`).
  - Label: `Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill")` → **`.labelStyle(.iconOnly)`** (`:506`) → **`.controlPlate()`** (`:507`).
  - a11y (`:509`), id `completeButton` (`:510`).
  - **No `.buttonStyle`.**

### 1.7 Mic button (both platforms; bottom bar)
- **`ContentView.swift:531`** — `Button { Task { await viewModel.dictation.startDictation() } }`.
  - Label: `Image(systemName: "mic.fill")` → **`.font(.title2)`** (`:535`) → **`.controlPlate()`** (`:536`).
  - a11y `"Dictate reminder"` (`:538`), id `dictateButton` (`:539`).
  - Shared across iOS/macOS (`micButton` referenced in `bottomBar` at `:674`/`#else :677` and in `actionCluster` at `:517`). **No `.buttonStyle`.**

### 1.8 Upgrade prompt button (iOS bottom-bar, freemium gate)
- Instantiated at **`ContentView.swift:524`** (`UpgradePromptButton(isPresented: $isShowingPurchase)`); struct at **`PurchaseSettingsView.swift:175`**.
  - **`PurchaseSettingsView.swift:179`** — `Button { isPresented.wrappedValue = true }`.
  - Label: `Label("Upgrade to unlimited", systemImage: "lock.fill")` → `.font(.headline)` (`:183`) → **`.foregroundStyle(.white)`** (`:184`) → `.frame(maxWidth: .infinity)` (`:185`) → `.padding(.vertical, 14)` (`:186`) → `.padding(.horizontal, 24)` (`:187`) → **`.background(.blue, in: Capsule())`** (`:188`) → **`.shadow(radius: 4)`** (`:189`).
  - **`.buttonStyle(.plain)`** (`:191`), `.padding(.horizontal, 24)` (`:192`), a11y (`:193`), id `upgradeButton` (`:194`).

### 1.9 iOS bottom-bar Skip (action-cluster variant; also hosts the 3-option confirmation dialog)
- **`ContentView+ActionMenu.swift:31`** — `Button { if showActionMenu { …present dialog… } else { viewModel.skipCurrentReminder() } }` (inside `#if os(iOS)`).
  - Label: `Label(SharedStrings.skipAction, systemImage: "circle.slash")` → **`.labelStyle(.iconOnly)`** (`:40`) → **`.controlPlate()`** (`:41`).
  - a11y (`:43`), id `skipButton` (`:44`).
  - **`.confirmationDialog("Reminder", …)`** (`:46`) containing three more buttons:
    - **`:47`** `Button(SharedStrings.skipAction)` — zero styling.
    - **`:50`** `Button("Reschedule")`, id `rescheduleButton` (`:54`) — zero styling.
    - **`:55`** `Button(SharedStrings.deleteAction, role: .destructive)`, id `deleteButton` (`:58`) — zero styling.
  - **No `.buttonStyle` on any of these four.**

### 1.10 macOS bottom-bar buttons (`#if os(macOS)` block, `ContentView+ActionMenu.swift:68–163`)
- **`macCompleteButton` @ `:97`** — `Button { Task { await viewModel.completeCurrentReminder() } }`. Label `Label(…checkmark.circle.fill)` → **`.labelStyle(.iconOnly)`** (`:101`) → **`.font(.title)`** (`:102`). **`.tint(.green)`** (`:104`), **`.keyboardShortcut("c", modifiers: [])`** (`:105`), id `completeButton` (`:107`). **No `.buttonStyle`** — relies on macOS default button chrome.
- **`macActionMenu` (Menu, not Button) @ `:112`** — `Menu { … } label: { Label(SharedStrings.skipAction, systemImage: "circle.slash") .labelStyle(.iconOnly) (:125) .font(.title) (:126) }`, **`.tint(.orange)`** (`:128`), **`.keyboardShortcut("s")`** (`:129`), id `skipButton` (`:131`). Inner Menu buttons: skip (`:113`), reschedule (`:116`), delete `role: .destructive` with `.keyboardShortcut(.delete)` (`:119`, `:122`) — **zero styling**.
- **`macSkipButton` @ `:136`** — label `.labelStyle(.iconOnly)` (`:140`), `.font(.title)` (`:141`); **`.tint(.orange)`** (`:143`), **`.keyboardShortcut("s")`** (`:144`), id `skipButton` (`:146`). No buttonStyle.
- **`macDeleteButton` @ `:151`** — label `.labelStyle(.iconOnly)` (`:155`), `.font(.title)` (`:156`); **`.tint(.red)`** (`:158`), id `deleteButton` (`:160`). No buttonStyle.
- See §6 for the macOS-vs-iOS relevance of these (same logical buttons, plate-less on macOS).
- Also in this file, the shared reschedule sheet:
  - **`ContentView+ActionMenu.swift:189`** — toolbar `Button("Cancel") { isShowingRescheduleSheet = false }` inside `ToolbarItem(.cancellationAction)` — **zero styling modifiers.**

### 1.11 iOS nudge sheet (`ContentView+iOS.swift`, `#if os(iOS)`)
- **`:77`** — toolbar `Button("Cancel") { isShowingNudgeSheet = false }` — zero styling.
- **`:97`** — `nudgeViewInRemindersButton`: `Button { …viewModel.openInReminders… } label: { Label("View in Reminders", systemImage: "eye") }`, id (`:108`) — **zero styling modifiers.**
- **`:113`** — `nudgeDeleteButton`: `Button(role: .destructive) { …deleteNudgedReminder… } label: { Label(SharedStrings.deleteAction, systemImage: "trash") }`, id (`:121`) — **zero styling modifiers.**

### 1.12 Settings Done
- **`SettingsView.swift:161`** — toolbar `Button("Done") { dismiss() }` (`ToolbarItem(.confirmationAction)` at `:160`), id `settingsDoneButton` (`:164`) — **zero styling modifiers.**

### 1.13 Purchase screen buttons (`PurchaseSettingsView.swift`)
- **`:41`** — "Restore Purchases": `Button { Task { await entitlementStore.sync() } } label: { HStack { Text("Restore Purchases"); Spacer() } }`, id (`:49`) — **zero styling modifiers** (plain `List` row button).
- **`:85`** — "Try Again": `Button("Try Again") { loadError = nil; … }` → **`.buttonStyle(.bordered)`** (`:89`). No `.tint`.
- **`:103`** — purchase-price button: `Button { Task { await purchase(product) } } label: { if isPurchasing { ProgressView() } else { Text(product.displayPrice) } }` → **`.buttonStyle(.borderedProminent)`** (`:113`), **`.disabled(isPurchasing)`** (`:114`). No `.tint`.
- **`:179`** — UpgradePromptButton, see §1.8.
- **`:210`** — `PurchaseSheet` toolbar `Button("Done")`, id `:212` — **zero styling modifiers.**

### 1.14 Shared RescheduleSheet confirm
- **`RescheduleSheet.swift:33`** — `Button { …onReschedule(components)… } label: { Label("Reschedule", systemImage: "calendar.badge.plus") }`, id `rescheduleConfirmButton` (`:45`) — **zero styling modifiers.**

### 1.15 Background settings "Refresh wallpaper"
- **`BackgroundSettingsView.swift:56`** — `Button { Task { await backgroundImage.forceRefresh() } } label: { HStack { Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath"); Spacer(); if isRefreshing { ProgressView() } } }`, **`.disabled`** (`:67`), id `refreshWallpaperButton` (`:72`) — **zero styling modifiers** (plain `Form` row button).

### 1.16 iOS "Open Settings" (bottom-bar speech-unavailable path)
- **`ContentView.swift:695`** (inside `#if os(iOS)`) — `Button("Open Settings") { UIApplication.shared.open(…openSettingsURLString…) }` → **`.font(.caption)`** (`:699`). **No `.buttonStyle`**, no `.tint` — platform-default rendering in a plain `VStack`.

---

## 2. SingleThreadWatch (`WatchReminderView.swift`) — 12 buttons

No watch button has `.buttonStyle`; re: watch defaults, in-repo prior research explicitly documents the Complete/Skip pair as "Button`s using **default borderless watch button style** (no custom buttonStyle/background)" (`.pi/qrspi/alanvardy-var-692-make-buttons-more-visible/research.md:110`).

- **`:131`** — Complete: `Button { …completeCurrentReminder… } label: { Label(…checkmark.circle.fill) }`, **`.labelStyle(.iconOnly)`** (`:135`), **`.tint(.green)`** (`:137`), a11y (`:138`), id `completeButton` (`:139`).
- **`:142`** — Skip: `Button { …skip or present action menu… } label: { Label(…circle.slash) }`, **`.labelStyle(.iconOnly)`** (`:150`), **`.tint(.orange)`** (`:152`), a11y (`:153`), id `skipButton` (`:154`).
- **`:202`** — `refreshButton`: `Button("Refresh") { … }`, **`.disabled(viewModel.isRefreshing)`** (`:205`), id (`:206`) — zero styling. Reused by `allDoneState` (`:181`) and `noRemindersState` (`:233`).
- **`:212` / `:215` / `:219`** — `actionMenuDialogButtons` (`@ViewBuilder` at `:211`): Skip, Reschedule, Delete(`role: .destructive`) — **zero styling** (inside `confirmationDialog`, attached at `:285`).
- **`:250`** — `Button("Refresh")` inside the card's `confirmationDialog` (`.confirmationDialog` on the scroll area at `:249`), id (`:253`) — zero styling.
- **`:255`** — `Button(SharedStrings.deleteAction, role: .destructive)`, id `deleteButton` (`:258`) — zero styling.
- **`:262`** — nudge banner: `Button { viewModel.isShowingNudgeDialog = true } label: { Label(SharedStrings.skipNudgeTitle, systemImage: "exclamationmark.bubble").font(.caption) }`, id `skipNudgeBanner` (`:267`), with its own `.confirmationDialog` (`:269`) containing a delete `Button(role: .destructive)` at **`:270`** (id `nudgeDeleteButton` `:273`) — no tint/style on either.
- **`:305`** — `actionMenuRescheduleSheet` confirm `Button("Reschedule")`, id `rescheduleConfirmButton` (`:318`) — zero styling.
- **`:323`** — toolbar `Button("Cancel")`, inside `ToolbarItem(.cancellationAction)` (`:322`) — zero styling.

---

## 3. SingleThreadWidget (`NextThingWidget.swift`) — 2 buttons

- **`:149`** — `Button(intent: CompleteReminderIntent()) { Label(SharedStrings.completeAction, systemImage: "checkmark.circle.fill") }` → **`.labelStyle(.iconOnly)`** (`:151`) → **`.tint(.green)`** (`:153`) → **`.buttonStyle(.bordered)`** (`:154`) → a11y (`:155`) → id `completeButton` (`:156`).
- **`:158`** — `Button(intent: SkipReminderIntent()) { Label(SharedStrings.skipAction, systemImage: "circle.slash") }` → **`.labelStyle(.iconOnly)`** (`:160`) → **`.tint(.orange)`** (`:162`) → **`.buttonStyle(.bordered)`** (`:163`) → a11y (`:164`) → id `skipButton` (`:165`).

Widget context: `supportedFamilies` are systemSmall/Medium/Large (`NextThingWidget.swift:115`); buttons render only in the `.reminder` state (`reminderView` → `actionButtons` at `:231`).

---

## 4. (a) Buttons with explicit styling vs (b) platform-default buttons

### (a) Explicit style / plate is applied
| Button | file:line | Explicit treatment |
|---|---|---|
| Settings gear | ContentView.swift:195 | `.controlPlate()` on label (`:201`) — 56×56 circle fill+shadow |
| macOS Refresh | ContentView.swift:212 | `.controlPlate()` (`:217`) |
| iOS Undo | ContentView.swift:230 | `.controlPlate()` (`:235`) |
| iOS Complete (bottombar) | ContentView.swift:502 | `.controlPlate()` (`:507`) |
| Mic | ContentView.swift:531 | `.controlPlate()` (`:536`) |
| iOS Skip (bottombar) | ContentView+ActionMenu.swift:31 | `.controlPlate()` (`:41`) |
| Nudge banner | ReminderCardView.swift:144 | `.buttonStyle(.borderedProminent)` (`:153`) + `.tint(.white)` (`:154`) |
| Swipe-prompt Dismiss | ReminderCardView.swift:185 | `.buttonStyle(.borderedProminent)` (`:194`) + `.tint(.white)` (`:195`) |
| Try Again | PurchaseSettingsView.swift:85 | `.buttonStyle(.bordered)` (`:89`) |
| Purchase price | PurchaseSettingsView.swift:103 | `.buttonStyle(.borderedProminent)` (`:113`) |
| UpgradePromptButton | PurchaseSettingsView.swift:179 | `.buttonStyle(.plain)` (`:191`) + label `.background(.blue, in: Capsule())` (`:188`) + `.shadow(radius: 4)` (`:189`) + `.foregroundStyle(.white)` (`:184`) |
| Widget Complete | NextThingWidget.swift:149 | `.buttonStyle(.bordered)` (`:154`) + `.tint(.green)` |
| Widget Skip | NextThingWidget.swift:158 | `.buttonStyle(.bordered)` (`:163`) + `.tint(.orange)` |

### (b) Platform default style, no `.buttonStyle`, no plate
Split into two sub-groups by whether any non-style modifiers exist.

**(b1) Zero styling modifiers** (only a11y/disabled/padding/toolbar placement):
- ContentView.swift:438 (context "View in Reminders")
- ContentView+ActionMenu.swift:47, 50, 55 (dialog Skip/Reschedule/Delete), 189 (Cancel)
- ContentView+iOS.swift:77 (Cancel), 97 (View in Reminders), 113 (Delete, `role:.destructive` only)
- SettingsView.swift:161 (Done)
- PurchaseSettingsView.swift:41 (Restore Purchases), 210 (Done)
- RescheduleSheet.swift:33 (Reschedule)
- BackgroundSettingsView.swift:56 (refresh wallpaper; has `.disabled`)
- WatchReminderView.swift:202 (Refresh; `.disabled` only), 212, 215, 219 (dialog), 250, 255 (dialog), 262 (nudge banner — label has `.font(.caption)`), 270 (nudge delete), 305 (Reschedule confirm), 323 (Cancel)

**(b2) Platform default style + non-`.buttonStyle` modifiers** (tint/labelStyle/font/keyboardShortcut — appearance depends on platform default chrome + tint):
- ContentView.swift:447 (context Delete, `.tint(.red)` `:454`), 458 (swipe complete, `.tint(.green)`), 466 (swipe skip, `.tint(.orange)`), 695 (Open Settings, `.font(.caption)` `:699`)
- ContentView+ActionMenu.swift:97 (`macCompleteButton`), 112 (`macActionMenu` Menu), 136 (`macSkipButton`), 151 (`macDeleteButton`) — each `.labelStyle(.iconOnly)` + `.font(.title)` + `.tint` (+ `.keyboardShortcut` on all but delete)
- WatchReminderView.swift:131 (Complete) & 142 (Skip) — `.labelStyle(.iconOnly)` + `.tint`

Note: `macActionMenu` at ContentView+ActionMenu.swift:112 is a `Menu` (button-like control) carrying the same modifier set as the b2 Buttons.

---

## 5. Non-Button controls that reuse the button styling vocabulary
- `recordingIndicator` — `ContentView.swift:544–549`: `Image(systemName: "mic.fill").font(.title2).controlPlate(fill: .red, glyph: .white)` (not tappable).
- `creationFeedbackView(for:)` — `ContentView.swift:583–589`: `Image.controlPlate(fill: feedback.backgroundColor, glyph: .white)` (not tappable).
- `EmptyStateCard` body — `EmptyStateCard.swift:34`: `.cardPlate(fill: CardPlate.plateFill(for: colorScheme), padding: 20)` (non-interactive).
- Card card text plate — `ReminderCardView.swift:44`: `.cardPlate(…, restoresGeometry: true)`; swipe-prompt box — `ReminderCardView.swift:207`: `.cardPlate(fill: CardPlate.promptBoxFill)`.

---

## 6. Custom ButtonStyle structs — what actually exists

**There are no custom `ButtonStyle` conformances anywhere in the repo.** Grep for `ButtonStyle|ButtonStyleConfiguration|makeBody\(configuration` matches only a reflected-name string: `SingleThreadTests/SwipePromptTests.swift:51` (`"BorderedProminentButtonStyle"` — the built-in SwiftUI style, asserted via `String(describing:)` of the Dismiss button).

Custom button-adjacent types that DO exist (all `ViewModifier` or constants, none adapting `ButtonStyle`):
- **`ControlPlateModifier` (ViewModifier)** — `SingleThread/ControlPlateModifier.swift:17–40`. `body` at `:20–29`: `.foregroundStyle(resolvedGlyph)` (`:25`), `.frame(width: 56, height: 56)` (`:26`), `.background(resolvedFill, in: Circle())` (`:27`), `.shadow(radius: 4)` (`:28`); constants `plateSize 56` (`:33`), `lightPlateWhite 0.92` (`:34`), `darkGlyphWhite 0.15` (`:35`), `shadowRadius 4` (`:36`); scheme-adaptive fills (`:21–22`). Helper `extended View.controlPlate(fill:glyph:)` (`:51–55`). Applies *around* the Button's label — it does not replace or set any button style.
- **`cardPlate`** — `SingleThread/CardPlateModifier.swift:17–28`: padding → `RoundedRectangle(cornerRadius: CardPlate.cornerRadius).fill(fill)` background → optional negative padding (`:22–28`); helper `cardPlate(fill:padding:restoresGeometry:)` (`:29–51`; helper body `:34`–`51` per earlier read; file read shows helper at `:51–54`). Pure shape/padding — not a ButtonStyle.
- **`CardPlate` (enum constants)** — `SingleThread/CardPlate.swift:11–32`: `cornerRadius = 10` (`:16`), `promptBoxFill = Color(red: 0.16, green: 0.17, blue: 0.18)` (`:23`), `plateFill(for:)` dark → `.black` / light → `Color(red: 0.96, green: 0.95, blue: 0.94)` (`:29–31`).
- **`UpgradePromptButton` (custom View, not a style)** — `PurchaseSettingsView.swift:175–197` (see §1.8). It IS the one button that hand-draws its full look (blue Capsule + shadow) via `.buttonStyle(.plain)` to suppress platform chrome.

---

## 7. For identical view code: default Button on macOS vs iOS

Verified, in-repo evidence only:

1. **The task statement itself (in-repo)** — `.pi/qrspi/alanvardy-var-792-macos-button-rendering-anomalies/task.md:3`:
   > "On macOS, buttons in SingleThread render with translucent squares — the platform-default button chrome (bezel) — around them, while on iPhone and iPad the same views render chrome-less."
2. **Per-platform bifurcation of the SAME logical buttons** — strongest code evidence. The bottom-bar Complete/Skip exist twice with identical actions:
   - iOS: `completeButton` (`ContentView.swift:502`) and `skipButton` (`ContentView+ActionMenu.swift:31`) draw their own chrome with `.controlPlate()` (`:507`, `:41`) — i.e., the iOS default would otherwise supply none.
   - macOS: `macCompleteButton`/`macSkipButton`/`macDeleteButton` (`ContentView+ActionMenu.swift:97/136/151`) carry no plate, no `.buttonStyle`, only `.labelStyle(.iconOnly)` + `.font(.title)` + `.tint` (+ keyboard shortcuts) — i.e., the macOS default (bordered/bezel chrome) is relied on to make them visible.
3. **/wiki-style doc for same split in prior work** — `.pi/qrspi/alanvardy-var-783-work-on-settings-in-macos/research.md:57`: "macOS `actionButtons` HStack (no `controlPlate`)" vs iOS `controlPlate` sites listed at `:83–84`.
4. **Watch default is also chrome-less** — `.pi/qrspi/alanvardy-var-692-make-buttons-more-visible/research.md:110`: watch Complete/Skip use "default borderless watch button style (no custom buttonStyle/background)". No `.buttonStyle` exists anywhere in `SingleThreadWatch/` (grep-verified).
5. **Motivation comment for manual chrome on the shared targets** — `ControlPlateModifier.swift:3–4`: "A scheme-adaptive circular plate that ensures controls are legible against any background photo", and `:43–44` "so the control remains visible against any background" — i.e., on target platforms where default buttons are chrome-less, the app supplies its own plate.
6. **Deliberately styled buttons escape the divergence** — everywhere an explicit `.buttonStyle` is set, it is set identically with no `#if os` branching: `.borderedProminent`+`.tint(.white)` nudge/Dismiss (`ReminderCardView.swift:153–154`, `194–195`), `.bordered` Try Again (`PurchaseSettingsView.swift:89`), `.borderedProminent` purchase (`:113`), `.plain` upgrade (`:191`), widget `.bordered` (`NextThingWidget.swift:154,163`). A test pins that this styled button reflects as `BorderedProminentButtonStyle` on the platform it runs on (`SwipePromptTests.swift:51`).
7. **Platform-default (unstyled) buttons affected by the split** are exactly the §4(b) list: toolbar Done/Cancel, `List`/`Form` row buttons (Restore Purchases, Refresh wallpaper), dialog buttons, watch buttons, and the macOS bottom-bar cluster — none set `.buttonStyle`, so each inherits whatever the default style draws **per runtime platform** for identical view code.

**Bottom line (factual, no prescription):** for identical Button/view code with no `.buttonStyle`, the codebase contains no per-platform styling branch that changes modifier composition — the divergence is entirely from the system's default button style rendering: macOS draws the translucent "bezel" chrome (task.md:3), iPhone/iPad draw chrome-less (task.md:3; watch borderless per research.md:110), which is why the same logical buttons are given `.controlPlate()` on iOS but left bare on macOS, per the `#if os(iOS)`/`#if os(macOS)` splits in §1.6/§1.10.

---

## Command verification log
- `grep -n "Button(" / "\\bButton\\b"` across the three target dirs → 48 call sites (34+12+2).
- `grep "buttonStyle"` repo-wide → 8 hits (7 button styles + 1 `.listStyle(.plain)`).
- `grep "\.tint("` → 14 sites; `\.controlSize(` → 0 sites; `\.labelStyle(` → 10 sites (0 non-button); `\.shadow(` → 2 sites (`ControlPlateModifier.swift:28`, `PurchaseSettingsView.swift:189`).
- Read in full: `ContentView.swift` (708 lines), `ContentView+ActionMenu.swift`, `ContentView+iOS.swift`, `ReminderCardView.swift`, `PurchaseSettingsView.swift`, `SettingsView.swift`, `RescheduleSheet.swift`, `BackgroundSettingsView.swift`, `ControlPlateModifier.swift`, `CardPlate.swift`, `CardPlateModifier.swift`, `EmptyStateCard.swift`, `SingleThreadApp.swift`, `WatchReminderView.swift` (461 lines), `NextThingWidget.swift` (277 lines), `SwipePromptTests.swift` (partial).