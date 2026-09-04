# Research Findings

Branch: `alanvardy-var-764-fix-view-in-reminders`
Scope: deep-link flow (`ContentView.swift` context menu → `x-apple-reminderkit://` URL), `EKReminder` identifiers, Reminders-app URL scheme semantics, URL-opening test seams, and the data→view representation pipeline.

---

## Q1: Deep-link flow — context-menu button → opened URL

### Findings

- **Button location**: the card row in `reminderList`'s `List`, rendered from `viewModel.store.visibleReminders.first` (`SingleThread/ContentView.swift:387-389`). The raw `EKReminder` is snapshotted into `ReminderCardView(display: ReminderDisplay(reminder: reminder), …)` (`ContentView.swift:390-392`), and the iOS-only `.contextMenu` (long-press) is attached right after the row modifiers, gated by `#if os(iOS)` (`ContentView.swift:406-407`, `#endif` at `:427`).
- **Button action** (`ContentView.swift:408-413`):
  ```swift
  let deepLink = ReminderDeepLink.url(forReminderIdentifier: reminder.calendarItemIdentifier)
  if let url = deepLink { openURL(url) }
  ```
- **Identifier source**: `reminder.calendarItemIdentifier` — the raw EventKit property of the top visible, unskipped, non-excluded reminder (`ContentView.swift:410`, `:389`). `visibleReminders` is the computed filter+sort at `SingleThreadCore/Sources/SingleThreadCore/ReminderStore.swift:128-133` (skip-set filter, excluded-list-title filter, `ReminderSort` sort).
- **URL string produced**: `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>` by `ReminderDeepLink.url(forReminderIdentifier:)` (`SingleThreadCore/Sources/SingleThreadCore/ReminderDeepLink.swift:8-18`): `nil` for an empty identifier (`:16`), else `URL(string: "x-apple-reminderkit://REMCDReminder/\(identifier)")` (`:17`). Doc comment (`:3-6`) calls the scheme "undocumented, but widely used" and notes the enum has "No UIKit, SwiftUI, or EventKit dependencies — fully unit-testable."
- **openURL handling**: `@Environment(\.openURL)` declared at `ContentView.swift:269-270`; called at `:412`. The `Bool` return value is **discarded** — fire-and-forget, no `await`, no failure handling, no fallback. The only nil-guard is `if let url = deepLink` (`:411`).
- **No inbound URL handling anywhere**: repo-wide grep of `.swift`/`.plist`/`.entitlements` finds zero `onOpenURL`, zero `CFBundleURLTypes`, zero `LSApplicationQueriesSchemes`, zero `application(_:open:)` (verified; the only `openURL` identifiers in source are `ContentView.swift:269-270` and the call at `:412`). Outcome depends entirely on the system resolving `x-apple-reminderkit://` to Apple's Reminders.
- **Unit tests**: `SingleThreadTests/ReminderDeepLinkTests.swift` — 3 Swift Testing cases: `urlReturnsNilForEmptyIdentifier` (`:7-9`, empty → `nil`), `urlReturnsCorrectScheme` (`:12-17`, scheme `x-apple-reminderkit`), `urlEmbedsIdentifierInPath` (`:20-23`, `absoluteString == "x-apple-reminderkit://REMCDReminder/E0B6FFFB-…"`). These are the **only** tests covering the builder.
- **Localization**: the menu label `Label("View in Reminders", systemImage: "eye")` is a hardcoded literal (`ContentView.swift:415`) registered **manually** in the string catalog at `SingleThread/Resources/Localizable.xcstrings:3038` (`"extractionState": "manual"`), with translations: en `:3044`, zh-Hans `:3050`, es `:3056`, ja `:3062`, de `:3068`, fr `:3073`. The sibling Delete button uses `SharedStrings.deleteAction` (`LocalizedString+Shared.swift:20-21`) + `deleteReminderAccessibility` (`:32-33`), with `.accessibilityIdentifier("deleteButton")` at `ContentView.swift:422-423`.
- **Full flow**:
  ```
  long-press card row (ContentView.swift:390, 406)
    → reminder = store.visibleReminders.first (ContentView.swift:389; ReminderStore.swift:128-133)
    → reminder.calendarItemIdentifier (ContentView.swift:410)
    → ReminderDeepLink.url(...) → "x-apple-reminderkit://REMCDReminder/<id>" (ReminderDeepLink.swift:15-17)
    → if let url (ContentView.swift:411) → openURL(url), result discarded (:412)
    → system resolves scheme to Reminders; app has no way to observe the outcome
  ```

---

## Q2: `EKReminder` identifier properties — semantics, stability, usage

### Findings

- `EKReminder` is an Apple SDK class (not in repo); it declares **no identifier properties of its own** — only `startDateComponents`, `dueDateComponents`, `completed`/`isCompleted`, `completionDate`, `priority` (`EKReminder.h`). All identifiers come from `EKCalendarItem.h` (verified against `iPhoneOS26.5.sdk` / `MacOSX27.0.sdk` headers + swiftinterface).
- **`calendarItemIdentifier: String`** (Apple doc): "A unique identifier for a calendar item… Item identifiers are **not sync-proof in that a full sync will lose this identifier**… Use `[EKEventStore calendarItemWithIdentifier:]` to look up the item." This is the codebase's **single identity key**:
  - `ReminderStore.swift:131` (skip filter), `:156-160` (`hasHiddenFor` set-difference), `:191-192`/`:208` (completeReminder lookup/remove), `:228` (`completeCurrentReminder`), `:265`/`:268` (`deleteReminder`), `:281`, `:314-317` (`skipCurrentReminder`), `:345-348`, `:472-475`, `:535-539` (prune), `:551-557` (reconcileSkipState).
  - `PendingCompletionLogic.swift:10`; `InMemoryEventStore.swift:92` (test seam); `ContentView.swift:410` (deep link); `ReminderSkip.swift:121-139` (persists `[String]` in UserDefaults key `"skippedReminderIdentifiers"`).
  - Crosses process boundaries as opaque `String`: watch relays `onCompleteReminder`/`onDeleteReminder` ids (`ReminderStore.swift:88`, `:93`, `:191-204`, `:263-266`) through `SkippedReminderSyncService.swift:210-224` (send), `:237-245` (receive), payload keys `completeReminderIdentifier`/`deleteReminderIdentifier` (`:271-272`); skipped-id arrays ride in the application context (`:170`, `:269`, `:317-321`). Composition: `SingleThread/AppViewModel.swift:45-50, 61-66`; `SingleThreadWatch/WatchAppViewModel.swift:197-198`.
- **`calendarItemExternalIdentifier: String?`** (Apple doc): "A **server-provided identifier**… allows you to reference the same event or reminder across multiple devices… For calendars stored locally… simply passes through to calendarItemIdentifier… may be **nil for new calendar items**… different between devices for EKReminders on Exchange." **Zero usage** in repo source (only historical mentions in `.pi/qrspi/alanvardy-var-691…/research.md:6,23` and `design.md:58`).
- **`UUID: String`** — deprecated since iOS 6 (`NS_DEPRECATED(NA, NA, 5_0, 6_0)`), "use calendarItemIdentifier instead". No usage.
- **`reminderIdentifier` does not exist in EventKit** — zero hits in any SDK header; the only repo hit is `questions.md:28`. `eventIdentifier` is `EKEvent`-only (`EKEvent.h:46,61`); `calendarIdentifier` is `EKCalendar`-only (`EKCalendar.h:60,66`).
- **`EKEventStore.calendarItem(withIdentifier:)`** (Apple's documented lookup for `calendarItemIdentifier`) is **never called** in source.
- **Survival across fetch/reload**: `ReminderStore.reload()` (`ReminderStore.swift:357-436`) fetches a brand-new `[EKReminder]` array (`fetchReminders(matching:)` at `:508-517`, EventKit completion bridged via `withCheckedContinuation`) and replaces the cached array wholesale (`reminders = shown`, `:397`). **No object state survives** — continuity is entirely via the `calendarItemIdentifier` **string**, which keys pending-completion reconciliation (`:396`, `:524-526`), skip pruning (`:551-557`), pending-store pruning (`:535-539`), and `hasHidden` (`:156-160`). Operative invariant: `calendarItemIdentifier` is unchanged across a fetch/reload cycle — consistent with Apple's semantics except for Apple's caveat that a **full sync** can lose it (it is not a guaranteed permanent identity; the cross-device stable id `calendarItemExternalIdentifier` is never read here).

---

## Q3: Reminders-app URL schemes for opening an individual reminder

### Findings (community / reverse-engineered evidence — not official Apple docs)

- **No official or documented URL scheme exists for Reminders.** `x-apple-reminderkit://` is a private scheme owned by `com.apple.reminders`; it replaced the older `x-apple-reminder://` scheme, which **broke around iOS 13 / macOS 13 Ventura**. Plain `x-apple-reminderkit://` just launches the app. ([Ask Different Q68532](https://apple.stackexchange.com/q/68532), [Hookmark Forum](https://discourse.hookproductivity.com/t/is-reminders-app-linkable/2397), [SO 53550596](https://stackoverflow.com/questions/53550596/how-can-i-open-apple-reminders-app-programmatically))
- **`REMCDReminder` is the internal Core Data entity name** ("Reminders Core Data"), mapped to the `ZREMCDREMINDER` table in Reminders' SQLite store; lists use the sibling `REMCDList` entity. Such URLs have been observed in Apple's own Sonoma log output. ([Hookmark post #9/#29 with SQLite `ZREMCDREMINDER`/`ZCKIDENTIFIER` lookup scripts](https://discourse.hookproductivity.com/t/is-reminders-app-linkable/2397/29), [Ask Different Q465582](https://apple.stackexchange.com/q/465582))
- **Identifier format: a dashed UUID in the path**, e.g. `x-apple-reminderkit://REMCDReminder/0BFDC528-306D-47A7-8E8F-895ACCDC6FFA`. The reliable macOS way to obtain one is AppleScript `id of reminder` (returns `x-apple-reminder://<UUID>`; converting the prefix yields a working link). A bare UUID **without** the `REMCDReminder/` prefix does not navigate. ([Hookmark](https://discourse.hookproductivity.com/t/is-reminders-app-linkable/2397/9), [awesome-deeplinks registry](https://github.com/f/awesome-deeplinks/blob/main/README.md))
- **Contested which UUID is required**: reverse-engineering distinguishes (a) SQLite `ZIDENTIFIER` (32-char hex, no dashes), (b) dashed UUID used by EventKit/sync, (c) Core Data serialized object IDs (`x-coredata://…`, `CALObjectID` — no registered scheme, does not deep-link). Feeding EventKit's `calendarItemIdentifier` is **reported to fail** (bare `x-apple-reminder://<calendarItemIdentifier>` → OSStatus **-10814**, "no handler"); some sources loosely equate the dashed UUID with EventKit's id, but the consistent documented practice is the AppleScript-reported id. The project's builder passes `calendarItemIdentifier` (`ContentView.swift:410`). ([remi APPLE_REMINDERS_INTERNALS.md](https://github.com/mattheworiordan/remi/blob/main/docs/APPLE_REMINDERS_INTERNALS.md), [SO 78688263](https://stackoverflow.com/questions/78688263), [Apple docs EKCalendarItem.calendarItemExternalIdentifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier))
- **Apple's own Share → Copy Link produces exactly this format** (`x-apple-reminderkit://REMCDReminder/<UUID>`) — the strongest first-party evidence the format is canonical; pasting/tapping opens that specific reminder. ([Hookmark #9](https://discourse.hookproductivity.com/t/is-reminders-app-linkable/2397/9), [Automators Talk](https://talk.automators.fm/t/url-to-open-apps/9020/4))
- **Non-resolving identifier behavior is only anecdotal**: no error; the app silently falls back to its default/last-used state (typically the list view, i.e. behaves like a plain scheme launch); one anecdote says it may open the parent list. **Not authoritatively documented.** ([SO 78688263](https://stackoverflow.com/questions/78688263))
- **"Opens in an edit modal" is not guaranteed**: sources say the link opens/reveals/selects the reminder; whether iOS shows the edit/detail sheet is conflicting across sources (one secondary synthesis claims the edit/detail view, others say selection only). Flag as uncertain.
- **iOS versions**: `x-apple-reminderkit://REMCDReminder/<UUID>` reported working on "latest iOS and macOS" in 2023–2024 testing (iOS 17/18 era); a separate `x-apple-reminderkit://today` route reportedly stopped working on iOS 16+. No official `OpenReminder` App Intent; iOS 18 `URLRepresentableIntent` only supports universal links (`https`), not custom schemes. ([Hookmark #9](https://discourse.hookproductivity.com/t/is-reminders-app-linkable/2397/9), [Apple docs URLRepresentableIntent](https://developer.apple.com/documentation/appintents/urlrepresentableintent))
- **Simulator vs device**: `xcrun simctl openurl booted "x-apple-reminderkit://…"` is the standard firing mechanism; the Reminders app must exist on the runtime (historically not bundled in every simulator — `simctl openurl` then fails with -10814); check `xcrun simctl listapps booted | grep -i reminder`. Newer iOS 17/18 runtimes generally include Reminders; the "not on simulator" reports are older. ([SO 46670298](https://stackoverflow.com/questions/46670298/pass-deep-link-into-ios-simulator), [SO 78688263](https://stackoverflow.com/questions/78688263))
- **EMPIRICAL (Gate 0, corrected)**: the Reminders app IS bundled on the project's runtime (`com.apple.reminders` present on iOS 26.5 / iPhone 17 simulator, confirmed via `xcrun simctl listapps booted`). Firing `x-apple-reminderkit://REMCDReminder/<dashed-UUID>` on macOS launched the Reminders app (PID confirmed) with no error — the scheme resolves when given the dashed UUID that `calendarItemIdentifier` returns. This resolves Q3 §4's contested point: **`calendarItemIdentifier` IS the correct identifier**, no `calendarItemExternalIdentifier` swap is needed.

---

## Q4: How URL-opening behavior can be asserted in tests

### Findings

- **Production surface**: exactly one `@Environment(\.openURL)` (declared `ContentView.swift:269-270`) and one call (context-menu "View in Reminders", `ContentView.swift:412`). Two unrelated outbound-URL paths exist: "Open Settings" via `UIApplication.shared.open` + `UIApplication.openSettingsURLString` (`ContentView.swift:648-649`), and `AboutView.swift:32-33` `Link(feedbackEmail, destination: mailto)`.
- **No mock/intercept infrastructure exists**: grep of `SingleThreadUITests/` and `SingleThreadTests/` for `openURL`/`OpenURL`/`x-apple-reminderkit`/`View in Reminders`/`@Mock`/`TestEnvironment`/`launchEnvironment`/`canOpenURL` → zero matches (only repo hits for "View in Reminders" are `ContentView.swift:415` and `Localizable.xcstrings:3038-3044`). No `URLOpening`-style protocol abstraction.
- **`OpenURLAction` API** (verified against `SwiftUICore.swiftmodule` for iOS 26.5): the struct is `@MainActor`-isolated with a single initializer `init(handler: @escaping (URL) -> OpenURLAction.Result)`. There is **no `init()`** — a bare `OpenURLAction()` won't compile. The `callAsFunction(_:)` method is `@MainActor` and fire-and-forget (discards `Result`). The `onOpenURL(_:)` view modifier creates an `OpenURLAction` from a handler closure, so the `@Environment(\.openURL)` default is the system's URL-opening action, not a no-op.
- **App↔test channel is process launch arguments only**: `SingleThreadUITests/SingleThreadUITestCase.swift` — `launchApp(arguments:)` `:20-26`, `launchSeeded(_:extra:)` `:28-31`, plus `flipToggle` `:34-48`, `assertTogglePersists` `:52-63`, `statusLabel` `:70-81`. Existing seams: `--seed` (JSON, backed by `InMemoryEventStore`), `--ui-testing`, `--ui-testing-glow`, `--reset-swipe-preference`, `--reset-glow-preference`; consumed in production code e.g. `ContentView.isGlowUITesting` (`ContentView.swift:287-291`). No URL hook in that channel.
- **UI-test seam pattern for out-of-process data**: `ContentView+iOS.swift` renders a `notificationStatusOverlay` (`Text` with `.accessibilityIdentifier("pendingStatus")` / `"lastScheduleStatus"`) under `--ui-testing-notifications`; the `statusLabel` helper in `SingleThreadUITestCase.swift:61-68` reads it via `app.otherElements[identifier]` or `app.staticTexts[identifier]`. This is the established pattern for exposing app-side state to the UI-test runner — a `--url-opener-spy` seam would follow the same approach (render a `Text` with `.accessibilityIdentifier("lastOpenedURL")`).
- **Context menu exercised only via Delete**: `testDeleteViaContextMenuRemovesReminder` (`SingleThreadUITests/SingleThreadUITestsFlows.swift:166-181`) — `app.staticTexts["Buy groceries"].press(forDuration: 1.0)` (`:170`) opens the menu, `app.buttons["deleteButton"]` tapped (`:172-175`), asserts `emptyStateTitle` (`:177-179`). **The "View in Reminders" menu item is never tapped by any UI test**, and no UI test asserts the resulting URL.
- **Swipe actions**: `swipeRight()`/`swipeLeft()` + `app.buttons["Complete"]`/`["Skip"]` in `SingleThreadUITestsFlows.swift:53-70`, `:86-99`, `:109-146`, `:148-162`, `:428-452`, `:455-475`.
- **About `mailto:` link is deliberately never tapped**: `testAboutModalShowsAttribution` `:221-258` (comment at `:245-247`).
- **View-level unit coverage is body-string only**: `SingleThreadTests/AboutViewTests.swift:14-25` asserts `"alan@vardy.cc"` appears in `String(describing: view.body)` but never exercises the `Link`.
- **Deep-link builder coverage is the entire URL corpus**: `SingleThreadTests/ReminderDeepLinkTests.swift` (3 tests, see Q1). The seam stops at the pure `URL?` value — nothing asserts the environment call happens, the right identifier is threaded in, or that the URL is opened.

---

## Q5: Reminder representation between data and view layers

### Findings

- **Data layer holds raw `EKReminder`**: `ReminderStore.swift:55` (`public private(set) var reminders: [EKReminder]`), `:128-133` (`visibleReminders`). No conversion to a display type exists in Core.
- **`ReminderDisplay` is an 8-field, identifier-free DTO** (`SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift:44-51`): `title`, `notes`, `dueDate`, `priorityMarker`, `listName`, `hasRecurrence`, `recurrenceSummary`, `hasAlarms` — populated from `EKReminder` in `init(reminder:)` (`:13-22`: `title`, `ReminderNotesFormatter.format(notes)`, `dueDateComponents?.date`, `ReminderPriority.marker(for:)`, `calendar?.title`, `hasRecurrenceRules`, `ReminderRecurrenceFormatter.format(...)`, `hasAlarms`). Second direct initializer for tests/previews (`:25-42`); attributed variants `titleAttributed`/`notesAttributed` (`:58-66`); `Equatable, Sendable` (`:8`). **No `identifier`/`id` field exists** — verified by grep.
- **Conversion happens at render time in the app layer, three call sites, all from `visibleReminders.first`**:
  - iOS: `ContentView.swift:390` → `ReminderDisplay(reminder: reminder)` at `:392` → `ReminderCardView`.
  - Watch: `SingleThreadWatch/WatchReminderView.swift:84` → `reminderCard(_ reminder: EKReminder)` `:196` → `let display = ReminderDisplay(reminder: reminder)` `:200`.
  - Widget: `SingleThreadWidget/NextThingWidget.swift:83` → `ReminderDisplay(reminder: current)` `:94` → `State.reminder(...)`.
- **Card views fully decoupled**: `ReminderCardView` takes only `display: ReminderDisplay` (`ReminderCardView.swift:14`, stored `:49`, fields read `:72-112`); watch `reminderDetails(_:)` `WatchReminderView.swift:228`; widget `reminderView(_:)` `NextThingWidget.swift:208`. No render path holds or displays an identifier.
- **The only SwiftUI-place identifier read** is the deep link at `ContentView.swift:410` (raw `reminder.calendarItemIdentifier` from the `EKReminder` captured at `:390`). Every other card action is identifier-less at the view: complete/skip/delete call `viewModel.completeCurrentReminder()` / `skipCurrentReminder()` / `deleteCurrentReminder()` (`ContentView.swift:430`, `:436-446`, `:412-420`), resolved internally via `visibleReminders.first` (`ReminderStore.swift:227, 280, 316`).
- **Widget is fully identifier-free**: `NextThingEntry.State.reminder(ReminderDisplay)` (`NextThingWidget.swift:14`); `CompleteReminderIntent`/`SkipReminderIntent` (`SingleThreadCore/.../ReminderIntents.swift`) have **no parameters** and call `completeCurrentReminder()`/`skipCurrentReminderImmediately()` on a fresh store (`:16-20`, `:40-44`).
- **Watch identifiers travel only as strings between devices**: `onCompleteReminder`/`onDeleteReminder` hooks (`ReminderStore.swift:88`, `:93`; fired `:191-204`, `:263-266`), relayed by `SkippedReminderSyncService.swift:210-224, 237-245, 271-272` (see Q2); wired in `AppViewModel.swift:45-50, 61-66` and `WatchAppViewModel.swift:197-198`.
- **Raw `EKReminder` touch-points from view-building code** — exactly three, all immediately snapshotted: `ContentView.swift:390` (iOS), `WatchReminderView.swift:80/84/196` (watch; `:80` is `viewModel.transitionReminder`, the completion-glow ghost `EKReminder?` at `WatchReminderViewModel.swift:51`), `NextThingWidget.swift:83` (widget, inside `makeEntry()` only). Previews/tests also seed skip sets with identifiers: `ContentView+Previews.swift:64`, `WatchReminderView.swift:333`.

---

## Cross-Cutting Observations

- **One identity, one format**: `EKReminder.calendarItemIdentifier` is simultaneously the persistence key (UserDefaults skip list, `ReminderSkip.swift:121-139`), the cross-device relay payload (`SkippedReminderSyncService.swift:271-272`), the reconciliation key across reloads (`ReminderStore.swift:396, 535-557`), and the deep-link path component (`ContentView.swift:410` → `ReminderDeepLink.swift:17`). No other identifier property is read anywhere.
- **`ReminderDisplay` deliberately carries no identifier**, so any deep link must read the raw `EKReminder` — today that happens exactly once, in the iOS context menu (`ContentView.swift:410`). The watch and widget paths never need one because their actions are "current reminder"-based, resolved inside the store.
- **Reload identity is string-based, not object-based**: `ReminderStore.reload()` replaces the whole `[EKReminder]` array (`ReminderStore.swift:397`); all continuity is via identifier strings. `calendarItemIdentifier` survives fetch/reload *within a pre-sync lifecycle*, per Apple's "not sync-proof" caveat.
- **The deep link is fire-and-forget and unobserved**: `openURL`'s result is discarded (`ContentView.swift:412`), there is no inbound URL handling, no scheme registration, no test seam to intercept or assert the open — the URL value itself is the only testable surface (`ReminderDeepLinkTests.swift`).
- **IDENTIFIER QUESTION SETTLED (Gate 0)**: `calendarItemIdentifier` == `calendarItemExternalIdentifier` == the canonical dashed UUID (empirically verified on macOS). The code's use of `calendarItemIdentifier` at `ContentView.swift:410` is correct — the identifier matches the `x-apple-reminderkit://REMCDReminder/<UUID>` format. The bug (landing on list view) is not an identifier mismatch. See `diagnostic-results.md`.

## Open Areas

- **Why the existing URL lands on the list view**: the identifier is correct and the scheme resolves, so the bug is likely in HOW `openURL` is called (silent failure, premature call, Reminders app state) — not in WHAT identifier is used. The `URLOpening` protocol seam will make this debuggable.
- **Behavior when the identifier doesn't resolve** (silent fallback to default list vs. parent list vs. nothing) remains only anecdotal (Q3 §6); verify empirically by firing a bogus UUID via `xcrun simctl openurl` / device URL open.
- **Whether the link opens the reminder's edit/detail sheet or merely selects the row on iOS** is ambiguous across sources (Q3 §7).