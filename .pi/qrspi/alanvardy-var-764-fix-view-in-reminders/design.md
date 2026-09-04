# Design Discussion

## Current State

The iOS context-menu action "View in Reminders" (`ContentView.swift:408-413`)
builds a deep link via `ReminderDeepLink.url(forReminderIdentifier:)` using
`EKReminder.calendarItemIdentifier` and opens
`x-apple-reminderkit://REMCDReminder/<id>` through `@Environment(\.openURL)`
(`ContentView.swift:269-270`). The `openURL` result is discarded — fire-and-
forget (`:412`). The scheme is a private, undocumented Reminders-app URL; the
app registers no inbound URL handling and has no way to observe the outcome.

**The bug**: the Reminders app lands on the list view, not the specific
reminder. Community research suggests the `REMCDReminder` path expects a
dashed UUID that may not match `calendarItemIdentifier` — but the evidence is
contested and not empirically verified on this project's runtimes.

**Testing gap**: the deep-link builder has 3 unit tests
(`ReminderDeepLinkTests.swift:7-23`) verifying the URL string, but no test
exists for the context-menu tap itself, and no infrastructure exists to
intercept or assert `openURL`. The only context-menu UI test is Delete
(`SingleThreadUITestsFlows.swift:166-181`).

**Identifier landscape**: `EKReminder` exposes only `calendarItemIdentifier`
(`String`, "not sync-proof") and `calendarItemExternalIdentifier` (`String?`,
"server-provided … may be nil for new items"). The codebase uses
`calendarItemIdentifier` exclusively — as the persistence key, skip-set
identity, cross-device relay payload, and reload reconciliation key. The
`ReminderDisplay` DTO carries no identifier field (`ReminderDisplay.swift:44-51`).

## Desired End State

The "View in Reminders" context-menu action opens the specific reminder for
editing in Apple's Reminders app. Verification:

1. **Empirical proof**: firing `xcrun simctl openurl booted <url>` with the
   identifier from a seeded store opens the specific reminder (not the list).
2. **Unit test**: a `URLOpening` spy confirms the full pipeline — context menu
   → builder → correct URL opened.
3. **UI test**: a new context-menu test taps "View in Reminders" and asserts
   the URL was opened (via the spy, read from a launch-arg seam).

## Patterns to Follow

- **Protocol seam for testability**: `EventKitStoring` protocol in Core
  (`SingleThreadCore/Sources/SingleThreadCore/EventKitStoring.swift:1-56`) +
  `InMemoryEventStore` fake (`InMemoryEventStore.swift:1-143`). Same pattern
  for `SpeechTranscribing` in the app target (`SingleThread/ReminderDictation.swift:10-16`).
  We apply this to URL opening.

- **Injection through `ContentViewModel`**: `speechTranscriber: any SpeechTranscribing`
  (`SingleThread/ContentViewModel.swift:17`). The `URLOpening` abstraction
  follows the same path — a protocol injected into the view model, with a
  production wrapper that delegates to `@Environment(\.openURL)`.

- **Pure-function builder stays in Core**: `ReminderDeepLink` is a `nonisolated`
  enum with one static method (`ReminderDeepLink.swift:8-18`). It stays as-is;
  the protocol wraps the *opening* action, not the URL construction.

- **Launch-arg seam for UI tests**: `--seed '<json>'` pattern in
  `AppViewModel.makeStore(arguments:)` (`AppViewModel.swift:218-285`). A new
  argument (e.g. `--url-opener-spy`) or a `lastOpenedURL` key in the seed
  signals the UITest to read what was opened.

- **Context menu UI test pattern**: `testDeleteViaContextMenuRemovesReminder`
  (`SingleThreadUITestsFlows.swift:166-181`): long-press → find button →
  tap → assert. New "View in Reminders" UI test follows the same structure.

- **Pattern to NOT follow**: Reading `EKReminder` properties directly in
  SwiftUI views. The deep link is the only case (`ContentView.swift:410`),
  and it's a justified one-off. Do not add an `identifier` field to
  `ReminderDisplay` — it would be dead weight on watch, widget, and every
  preview/test constructor.

## Design Decisions

1. **Diagnostic-first**: before writing any code fix, verify empirically which
   identifier `x-apple-reminderkit://REMCDReminder/<X>` resolves to the
   specific reminder. Seed a store with a known reminder, extract its
   `calendarItemIdentifier`, fire `xcrun simctl openurl booted
   "x-apple-reminderkit://REMCDReminder/<id>"` and observe behavior. If it
   works — the code fix is only the test seam. If it doesn't — we have ground
   truth for which identifier property to use.

2. **Alternative identifier source — deferred**: wait for the diagnostic
   result. If `calendarItemIdentifier` fails, investigate
   `calendarItemExternalIdentifier` (documented "server-provided" UUID, nil
   for new items — `EKCalendarItem.h`). Do not add speculative fallback
   chains without evidence.

3. **Add `URLOpening` protocol seam**: a new `@MainActor protocol URLOpening`
   in the app target (`SingleThread/`) with one method: `func open(_ url: URL)`
   (mirrors `OpenURLAction.callAsFunction`). Production: a
   `SystemURLOpener` that wraps `@Environment(\.openURL)`, injected into
   `ContentViewModel`. Test: a `URLOpeningSpy` that records the last-opened
   URL. This gives us a unit-test assertion surface for the full pipeline.

4. **Keep fire-and-forget**: the `openURL` result remains discarded. The fix
   is the correct identifier; if the Reminders app can't open (simulator w/o
   the app, rare edge case), the user sees the same list-landing they get
   today. No failure alert, no `canOpenURL` check, no clipboard fallback.

5. **Keep `ReminderDisplay` identifier-free**: the `ReminderDisplay` DTO stays
   without an `identifier` field (`ReminderDisplay.swift:44-51`). The deep
   link is a one-off, iOS-only need; the existing local `EKReminder` capture
   at `ContentView.swift:390` provides the identifier. Adding a field every
   surface (watch, widget, card, tests, previews) sets and never reads is
   dead weight.

## What We're NOT Doing

- **No inbound URL scheme registration**: the app doesn't need to handle URLs.
- **No `ReminderDisplay` identifier field**: out of scope.
- **No failure UI**: no alerts, toasts, or clipboard fallback on open failure.
- **No watch or widget deep-link changes**: the watch and widget have no
  "View in Reminders" action and never need a reminder identifier for
  outbound navigation.
- **No `calendarItemExternalIdentifier` adoption**: unless the diagnostic
  proves `calendarItemIdentifier` is the wrong key.
- **No `EKEventStore.calendarItem(withIdentifier:)` lookup**: the deep link
  is an outbound URL, not an inbound EventKit query.

## Open Risks

1. **Identifier mismatch**: community evidence is divided on whether
   `calendarItemIdentifier` matches the REMCDReminder UUID. The diagnostic
   will settle this. If it doesn't match and `calendarItemExternalIdentifier`
   is nil for the user's reminders, we may have no reliable identifier for
   the scheme — a dead end.

2. **Apple could remove/change the scheme**: `x-apple-reminderkit://` is
   undocumented and private. It's survived since iOS 13+ but has no
   stability guarantee. The test seam protects against regressions from
   Apple-side changes, but doesn't prevent them.

3. **Simulator vs. device**: Reminders may not be available on every
   simulator runtime. The diagnostic must verify availability on the
   project's target runtimes (iPhone 17, iPad A16) before the fix can be
   validated. If Reminders is absent from the simulator, device-only testing
   is needed.

4. **Edit-sheet vs. selection behavior**: sources disagree on whether the
   link opens the reminder's edit/detail sheet or merely selects the row.
   The ticket says "open for editing" — but if the scheme only selects, the
   ticket may need scope adjustment.

5. **UI test seam for `openURL`**: the `URLOpening` spy needs a way to
   communicate its recorded URL back to the UI test process. The existing
   `--seed` seam writes state before launch; we may need a launch-arg or
   an `XCUIElement`-readable surface (e.g. an accessibility-labeled element
   that renders the last-opened URL) to assert the URL was opened from a
   UI test. This is the riskiest implementation detail.