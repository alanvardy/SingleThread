# Structure Outline

## Approach

Add a `URLOpening` protocol seam so the "View in Reminders" context-menu
action's URL open is testable. The existing `ReminderDeepLink` pure builder
(already tested) stays unchanged. The fix is the correct identifier (settled
by an empirical diagnostic) plus the protocol abstraction, injected into
`ContentViewModel` and asserted through a unit-test spy and a UI-test seam.

---

## Gate 0: Empirical Diagnostic (no code)

**What**: verify that `x-apple-reminderkit://REMCDReminder/<calendarItemIdentifier>`
resolves to the specific reminder on the project's target runtimes. This
settles the design's central open risk — whether `calendarItemIdentifier` is
the right key for the scheme.

If the link opens the specific reminder: proceed with the code stages below.
If it silently falls back to the list view (or the app isn't available on
simulator): return to `/3_design` — the design assumes a working identifier,
and a dead end here changes the scope.

**Check**:
1. Seed a reminder via the `--seed` launch-arg.
2. Extract its `calendarItemIdentifier` from the debugger or a temporary `print`.
3. Fire `xcrun simctl openurl booted "x-apple-reminderkit://REMCDReminder/<id>"`.
4. Observe: does the Reminders app land on the edit sheet or at least select the row?
5. Also fire a bogus UUID — observe the fallback behavior (list view?).

**No tests, no code.** This is a risk-gate. Outcome recorded in `<artifact-dir>/diagnostic-results.md`.

---

## Stage 1: `URLOpening` contract + production wrapper + test spy

**What**: the protocol abstraction over `OpenURLAction` — the foundation
contract every later stage consumes. The `SystemURLOpener` wraps the real
`@Environment(\.openURL)` value; the `URLOpeningSpy` records the last-opened
URL for unit tests. Neither knows about reminders or deep links.

**Files**:
- `SingleThread/URLOpening.swift` — new
- `SingleThreadTests/URLOpeningSpy.swift` — new (or inline in the test file)

**Key changes**:

```swift
// SingleThread/URLOpening.swift

@MainActor
protocol URLOpening: AnyObject {
    /// Opens the URL. Mirror of `OpenURLAction.callAsFunction`;
    /// the `Bool` / `OpenURLAction.Result` is discarded (fire-and-forget).
    func open(_ url: URL)
}

@MainActor
final class SystemURLOpener: URLOpening {
    let action: OpenURLAction
    init(action: OpenURLAction) { self.action = action }
    func open(_ url: URL) { action(url) }
}
```

```swift
// SingleThreadTests/URLOpeningSpy.swift

@MainActor
final class URLOpeningSpy: URLOpening {
    private(set) var openedURLs: [URL] = []
    var lastOpenedURL: URL? { openedURLs.last }
    func open(_ url: URL) { openedURLs.append(url) }
}
```

**Tests** (in `SingleThreadTests/URLOpeningTests.swift`):
- `spyRecordsOpenedURL` — assert `lastOpenedURL` matches the URL passed to `open(_:)`
- `spyAccumulatesMultipleOpens` — assert `openedURLs` count grows
- `systemURLOpenerForwards` — construct `OpenURLAction` with a handler that
  sets a captured flag; assert `SystemURLOpener.open(url)` invokes the handler

**Verify**: `make test SIM='iPhone 17,OS=26.0'` passes for the new test suite.

> **`URLOpening` is `AnyObject`-constrained** so the view model can store it
> as `any URLOpening` without a protocol-boxing `@MainActor` conflict, and so
> the spy can be shared with a UI-test-accessibility read path in Stage 3.

---

## Stage 2: `ContentViewModel` wiring (business logic)

**What**: the view model gains a `urlOpener` property and a single method that
threads `EKReminder.calendarItemIdentifier` → `ReminderDeepLink.url(…)` →
`urlOpener.open(url)`. The method is the only place the identifier is read for
URL purposes; the view calls it from the context menu.

**Files**:
- `SingleThread/ContentViewModel.swift` — modified
- `SingleThreadTests/ContentViewModelTests.swift` — new test cases

**Key changes**:

```swift
// ContentViewModel additions

let urlOpener: any URLOpening   // default: SystemURLOpener(action: OpenURLAction())

/// Builds the deep link for the given reminder and opens it.
/// Does nothing when the identifier is empty (sad path).
func openInReminders(_ reminder: EKReminder) {
    guard let url = ReminderDeepLink.url(forReminderIdentifier: reminder.calendarItemIdentifier)
    else { return }
    urlOpener.open(url)
}
```

**Init changed**: `init(store:backgroundImage:speechTranscriber:showCompletionGlow:urlOpener:)` —
`urlOpener` defaults to `SystemURLOpener(action: OpenURLAction())` so previews
and `AppViewModel` (which patches the real action later) compile without
touching every call site.

**Tests** (in `SingleThreadTests/ContentViewModelTests.swift`):
- `openInRemindersOpensCorrectURL` — inject a spy, pass an `EKReminder` with a
  known `calendarItemIdentifier`, assert `spy.lastOpenedURL?.absoluteString` matches
  `"x-apple-reminderkit://REMCDReminder/<identifier>"`
- `openInRemindersWithEmptyIdentifierDoesNothing` — reminder with empty
  `calendarItemIdentifier` → `spy.openedURLs` is empty
- `openInRemindersWithNilURLDoesNotCrash` — reminder with an identifier that
  produces a `nil` URL (edge case: empty string after the guard) → no crash

**Verify**: `make test SIM='iPhone 17,OS=26.0'` passes for the new test cases.

---

## Stage 3: View wiring + production injection + UI-test seam

**What**: `ContentView` replaces its direct `openURL` call with
`viewModel.openInReminders(reminder)`. `AppViewModel` injects the real
`OpenURLAction` from `SingleThreadApp`'s environment. Previews stay
working with the default no-op. A launch-arg `--url-opener-spy` seam makes
the last-opened URL readable from the UI test process via a hidden
accessibility element.

**Files**:
- `SingleThread/ContentView.swift` — context menu button action replaced
- `SingleThread/AppViewModel.swift` — `contentViewModel` injects `SystemURLOpener`
- `SingleThread/SingleThreadApp.swift` — captures `@Environment(\.openURL)` and passes it
- `SingleThread/ContentView+Previews.swift` — verify existing previews compile
- `SingleThread/AppViewModel.swift` — `--url-opener-spy` launch-arg branch

**Key changes**:

```swift
// ContentView.swift:412 — old
// let deepLink = ReminderDeepLink.url(forReminderIdentifier: reminder.calendarItemIdentifier)
// if let url = deepLink { openURL(url) }
// → new
// Button { viewModel.openInReminders(reminder) } label: { ... }

// AppViewModel.swift — contentViewModel computed property
// Patches the real OpenURLAction into the view model's urlOpener.
// When --url-opener-spy, injects a URLOpeningSpy instead and stores
// it for the accessibility-element read path.

// SingleThreadApp.swift — body
// @Environment(\.openURL) private var openURL
// → passes openURL through AppViewModel to ContentViewModel
```

**UI-test seam**: when `--url-opener-spy` is in launch arguments, `AppViewModel`
creates a `URLOpeningSpy` and injects it as `urlOpener`. `ContentView` renders
a zero-opacity `Text("spyURL-\(lastOpenedURLString)")` with
`.accessibilityIdentifier("lastOpenedURL")` so the UI test can read it.

**Tests**:
- **Build**: all existing tests + previews compile. The `openURL` environment
  value is no longer read directly in `ContentView`'s body.
- **Regression**: `make test` and `make ui-test` pass — no existing behavior
  changes (the "View in Reminders" button has no UI test yet, so no test to
  port).
- **Manual**: fire the app in the simulator, long-press, tap "View in
  Reminders" — Reminders opens (same UX as before, but now through the
  protocol).

**Verify**: `./scripts/test.sh` passes (format + lint + build + unit tests + UI tests).

---

## Stage 4: UI test — "View in Reminders" context menu

**What**: a new UI test that long-presses the reminder card, taps "View in
Reminders", and asserts the correct URL was opened. This is the end-to-end
regression guard for the fixed flow.

**Files**:
- `SingleThreadUITests/SingleThreadUITestsFlows.swift` — new test

**Key changes**:

```swift
// SingleThreadUITestsFlows.swift

@MainActor
func testViewInRemindersOpensURL() {
    let app = launchSeeded(
        #"{"reminders":[{"title":"Buy groceries","calendarItemIdentifier":"E0B6FFFB-F794-4E6C-8B58-ABD123456789"}]}"#,
        extra: ["--url-opener-spy"])

    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.staticTexts["Buy groceries"].press(forDuration: 1.0)

    let viewInReminders = app.buttons["View in Reminders"]
    XCTAssertTrue(viewInReminders.waitForExistence(timeout: 3),
                  "Long-press should reveal the 'View in Reminders' context action")
    viewInReminders.tap()

    let spyLabel = app.staticTexts["lastOpenedURL"]
    XCTAssertTrue(spyLabel.waitForExistence(timeout: 3))
    XCTAssertTrue(
        spyLabel.label.hasPrefix("spyURL-x-apple-reminderkit://REMCDReminder/E0B6FFFB-"),
        "Expected ReminderKit deep link, got: \(spyLabel.label)")
}
```

> **Note**: the `--seed` JSON needs a `calendarItemIdentifier` field added to
> `UITestingSeed.ReminderSeed` so the test can control the identifier. If the
> `InMemoryEventStore` `makeReminder` helper already assigns a deterministic
> identifier (or the real `EKReminder` does), this may be simpler — extract
> the identifier from the seeded reminder and assert against it.

**The seed shape depends on which identifier `InMemoryEventStore.makeReminder`
produces**: if the real `EKEventStore` assigns a UUID automatically, we can
read it from the spy's URL. If the identifier is random, the test asserts
against the scheme + path prefix instead of the full UUID string.

**Tests**: the new test itself.

**Verify**: `make ui-test SIM='iPhone 17,OS=26.0'` passes for the new test.

---

## Testing Checkpoints

| Stage | What must be green | Command |
|-------|--------------------|---------|
| Gate 0 | Diagnostic recorded in `diagnostic-results.md` | Manual `xcrun simctl openurl` |
| Stage 1 | `URLOpeningTests` (3 tests) | `make test -only-testing:SingleThreadTests/URLOpeningTests` |
| Stage 2 | Stage 1 + `ContentViewModelTests` (3 new test cases) | `make test` |
| Stage 3 | Full build + all existing tests + no regression | `./scripts/test.sh` |
| Stage 4 | Stage 3 + new UI test | `make ui-test` |

---

## Cross-Cutting Notes

- **`ReminderDeepLink` is not touched** — it's a pure, already-tested builder
  in Core. The new code is iOS-only (`SingleThread/` app target + test targets).
- **`ReminderDisplay` stays identifier-free** — the `EKReminder` flows directly
  from `ContentView.swift:389` to the new `openInReminders(_:)` method.
- **The `--seed` `calendarItemIdentifier` field** may need to be added to
  `UITestingSeed.ReminderSeed` (in `SingleThreadCore`) if the test needs to
  control the identifier. This is a small data-model addition, not a new
  layer.
- **If the diagnostic (Gate 0) finds `calendarItemIdentifier` doesn't work**:
  return to `/3_design`. The alternative (`calendarItemExternalIdentifier`)
  is nil for new reminders and may not be available. This is a scope change,
  not a structure problem.