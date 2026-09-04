# Design Discussion — Lock Screen Widget + Control Center Controls

## Current State

SingleThread ships one WidgetKit home-screen widget plus nothing else surface-wise.

- **One bundle, one widget.** `@main SingleThreadWidgetBundle: WidgetBundle` returns a single `NextThingWidget()` (`SingleThreadWidget/SingleThreadWidgetBundle.swift:5-8`). The extension point is `com.apple.widgetkit-extension` (`SingleThreadWidget/Info.plist:6-8`).
- **Home-screen only.** `NextThingWidget` is a `StaticConfiguration`, `kind = "NextThing"`, `supportedFamilies = [.systemSmall, .systemMedium, .systemLarge]` — no accessory families (`NextThingWidget.swift:113-128`). The view body has **no** `environment(\.widgetFamily)` branch; every state collapses to the same `messageView` / `reminderView` regardless of size (`NextThingWidget.swift:141-162`).
- **Entry state machine.** `NextThingEntry.State` = `noAccess` / `empty(hasHidden)` / `allDone` / `reminder(ReminderDisplay)` (`NextThingWidget.swift:10-15`). `makeEntry` (`@MainActor`, :61-108) builds a fresh `ReminderStore` per materialization, applies sort + show-* App Group flags, and maps to a state (:74-97). Timeline self-reschedules every 15 min (:53-55); the app also calls `WidgetCenter.shared.reloadAllTimelines()` on store mutation (`SingleThread/AppViewModel.swift:76-79`) and settings change (`SingleThread/SettingsViewModel.swift:15-22`).
- **Two widget intents already exist and are compiled into the extension.** `CompleteReminderIntent` / `SkipReminderIntent` live in `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift` (:7-25, :30-52), `isDiscoverable = false` (:15,:38). They reach the store the same way the app does — fresh `ReminderStore(loadsReminders: true)` + reload, then `completeCurrentReminder()` (:17-24) or `skipCurrentReminderImmediately()` (:40-51). Skip intentionally uses the synchronous immediate write because WidgetKit may suspend the extension right after `perform()` returns (`ReminderStore.swift:340-353`). Completes are freemium-gated via `canMutate` (`ReminderStore.swift:150-152`, cap 100 at `EntitlementStore.swift:57`).
- **Shared-state substrate.** All cross-process keys round-trip `AppGroup.defaults` (`AppGroup.swift:11,16-18`); the widget reads skipped/excluded/sort/show-* and performs its own writes (skip set and completion count) through the same store paths (`ReminderStore.swift:557-569` matrix).
- **The widget target is iOS-only** (`pbxproj:1019/1048`), deployment 18.7 (:1009/1040), Core is a package dependency of it (:355-357), and it already carries `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (:1008/:1039) because the extension process performs EventKit saves.
- **No widget test target exists** (conventions §2); widget rendering is exercised only by three `#Preview` timelines (`NextThingWidget.swift:257,274,286`). Intent tests pin configuration only — `perform()` is never executed (`ReminderIntentsTests.swift:11-32`).

## Desired End State

1. The existing widget also offers **Lock Screen accessory variants** — `accessoryInline`, `accessoryRectangular`, `accessoryCircular` — each showing the "next thing" in a size-appropriate form, with the existing home-screen `.systemSmall/Medium/Large` rendering untouched.
2. **Two Control Center controls** — `ControlWidgetButton` for one-tap **Complete** and **Skip** — reusing the existing intents verbatim, writing through the same App Group paths, and honoring the existing freemium gate.
3. New presentation/status logic lives in `SingleThreadCore` and is **unit-tested**; the accessory/control views stay thin renderers.

**Verification:**
- `make build` + `make test` green; full `./scripts/test.sh` (CI-identical) green before commit.
- Lock Screen gallery shows three accessory variants for SingleThread; each renders the next-reminder summary and a sensible minimal no-content state.
- Control Center gallery shows "Complete" and "Skip" controls for SingleThread; tapping them completes/skips the first visible reminder and respects the completion counter.

## Patterns to Follow

**Follow (match the existing widget's idioms):**
- **Thin widget file, shared logic in Core.** Keep the single-file widget shape (`NextThingWidget.swift`) but push any new formatting/status logic into `SingleThreadCore` — the package is already the widget's only dependency (`pbxproj:355-357`) and already unit-tested by `SingleThreadTests`.
- **Explicit `@MainActor` in extension code.** The widget target does *not* default to MainActor (only the two app targets do: `pbxproj:777/:827, :961/:989`). New Core/extension entry points must annotate `@MainActor` explicitly, matching `makeEntry` (`NextThingWidget.swift:61`) and the intent `perform()`s (`ReminderIntents.swift:17,40`); Core store types annotate themselves (`ReminderStore.swift:9`).
- **Reuse the store, never reimplement writes.** Controls must call `completeCurrentReminder()` / `skipCurrentReminderImmediately()` exactly like the intents do today (:40-51), so the phone's refetch / counter / `onSkipSetChanged` hooks stay on one code path.
- **`isDiscoverable = false`** stays for both intents — controls surface via the `ControlWidget`'s `.displayName`/`.description`, not via Shortcuts/Siri. The widget's existing intents already pin this (`ReminderIntentsTests.swift:11-32`).
- **App Group discipline.** Any new persisted state (none expected) must go through `AppGroup.defaults`, never `UserDefaults.standard` (conventions §3).
- **Accessibility identifiers on every stateful element** (existing: `emptyStateTitle` `NextThingWidget.swift:197`); new accessory/control labels get identifiers where a11y-relevant.

**Do NOT follow:**
- **The family-agnostic view.** It works for home-screen sizes but must be superseded for accessory families with a real `switch environment(\.widgetFamily)` — do not try to render `messageView` into a `accessoryCircular` frame.
- **The stale `ReminderDateFilter.swift:13` comment** claiming watch/widget both skip MainActor default — only the widget does (`pbxproj:961/:989` set it on watch). Don't propagate that claim into new comments.
- **No widget `.widgetURL` / deep link** exists today — don't invent one; scope is presentation + action only.

## Design Decisions

1. **Two stateless `ControlWidgetButton` controls** (Q1=A) — Complete and Skip, reusing `CompleteReminderIntent`/`SkipReminderIntent` verbatim. No `ControlWidgetToggle`, no value provider, no `ControlCenter.shared.reloadControls` wiring. Rationale: matches the ticket's literal wording, zero new intent/state code, and `isDiscoverable=false` is already correct for widget-only intents.

2. **Controls live in the existing `SingleThreadWidget` bundle** — declared as `ControlWidget` structs registered in `SingleThreadWidgetBundle` alongside `NextThingWidget()`. No new extension target, no new `NSExtensionPointIdentifier` (controls reuse `com.apple.widgetkit-extension`), no Info.plist change. The Core package dependency already puts the intents in the extension (`pbxproj:355-357`).

3. **All three accessory families ship** (Q2=A): `accessoryInline` (single short line — `"› <title>"`), `accessoryRectangular` (title + due date, compact `reminderView`), `accessoryCircular` (glyph-only, e.g. the reminder's priority/`checkmark` marker, no text). Existing home-screen families unchanged; accessory rendering gated behind a new `switch environment(\.widgetFamily)`.

4. **New presentation logic lives in `SingleThreadCore`** (Q4=A). Add a small shared formatter/status type — e.g. `NextThingSummary` returning compact title/due-date/text and a resolved "next / all-done / empty / no-access" status — consumed by the accessory views. This makes it unit-testable in `SingleThreadTests` (no widget test target exists).

5. **No-content accessory rendering is minimal** — a single SF Symbol plus one short word per state (`.allDone` → checkmark "Done", `.empty` → checklist, `.noAccess` → lock), sized for the family; `accessoryCircular` shows only the glyph.

6. **Testing strategy** (Q3=A): configuration-only intent tests mirror the existing `ReminderIntentsTests` pattern; all new Core presentation/status logic gets Swift-Testing unit tests (happy + sad paths, per conventions). No injectable store seam into the intent `perform()` bodies; no intent-execution tests.

7. **No UI/XCTest driving of Control Center or Lock Screen** — Control Center is not XCUITest-driveable (ticket's own fallback), and lock-screen widgets live in the extension process outside the app's window. Coverage = Core unit tests + `#Preview` timelines mirroring `NextThingWidget.swift:257,274,286` (which must gain the accessory-family previews). Stated explicitly in the PR.

8. **Reload semantics unchanged.** Home-screen + accessory widgets keep the 15-min timeline and app-side `WidgetCenter.reloadAllTimelines()` hooks. Controls need no reload path (stateless actions).

## What We're NOT Doing

- No `ControlWidgetToggle`, value providers, `ControlCenter.shared.reloadControls(...)`, or any stateful "has next" status on the controls — deferred, flagged as follow-up.
- No `AppIntentControlConfiguration` / `AppEntity`-driven configurable controls.
- No App Shortcuts / Siri / Spotlight discoverability (intents stay `isDiscoverable = false`).
- No refactor of existing home-screen views, the intent `perform()` bodies, or the `ReminderStore` skip/complete paths.
- No watch or macOS surface — widget + controls remain iOS-only (already true, `pbxproj:1019/1048`).
- No new extension target, Info.plist keys, or deployment-target changes (accessory families need iOS 16+; floor is 18.7, so the `verify_deployment_target` guard is untouched).
- No new persisted keys — the feature writes through existing skipped/count/App-Group paths only.

## Open Risks

- **Control Center gallery surfacing** needs on-device verification (extension embedded, `SKIP_INSTALL=NO`); simulator support for the gallery is limited. Can't be covered by `./scripts/test.sh`.
- **`accessoryCircular` may be near-useless** for "next thing" (glyph only) — accepted per Q2=A; revisit if it looks empty in practice.
- **Accessory frames are tiny** — no caption/dynamic-type room; watch the SwiftLint accessibility + hit-region rules (accessory views are non-interactive, which mitigates this).
- **`perform()` latency in the extension.** Complete does an EventKit save + 200 ms settle + reload (`ReminderStore.swift:236-268`); this already happens in the widget today, so not new, but Control Center's <1 s guidance is the budget to respect.
- **Widget/control-originated mutations don't push phone→watch immediately** (phone groups observer only diffs the 5 show-* prefs, `AppViewModel.swift:366-395`). A Control Center Complete/Skip appears on the watch only after the phone next republishes — same gap as the existing widget, accepted.
- **`WidgetBundle` can host `ControlWidget` alongside `Widget`** per Apple's iOS 18 template; the exact builder syntax is a Phase 4 detail — if a `ControlWidget` cannot sit in the same body, the plan will isolate it without a new target.