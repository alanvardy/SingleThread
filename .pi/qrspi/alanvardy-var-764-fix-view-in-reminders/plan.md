# Implementation Plan

## Overview

Add a `URLOpening` protocol seam so the "View in Reminders" context-menu
action is testable, then introduce a UI test that asserts the correct deep
link is opened. The identifier (`calendarItemIdentifier`) and URL builder
(`ReminderDeepLink`) are already correct; the change is purely adding the test
seam and wiring it through the view model.

## Phase 1: `URLOpening` contract + production wrapper + test spy

### Changes

#### 1. New protocol, production wrapper, and spy
**File**: `SingleThread/URLOpening.swift`
**Action**: create

```swift
import SwiftUI

/// Abstract over `OpenURLAction` so tests can intercept opened URLs.
/// `AnyObject`-constrained so a view model stores `any URLOpening`
/// without a protocol-boxing `@MainActor` conflict.
@MainActor
protocol URLOpening: AnyObject {
    func open(_ url: URL)
}

/// Production wrapper: delegates to the live `@Environment(\.openURL)` value.
@MainActor
final class SystemURLOpener: URLOpening {
    private let action: OpenURLAction
    init(action: OpenURLAction) { self.action = action }
    func open(_ url: URL) { action(url) }
}

/// Records every URL passed to `open(_:)` — test spy for unit + UI tests.
/// Lives in the app target (not `SingleThreadTests/`) because the
/// `--url-opener-spy` UI-test seam runs in the app process.
@MainActor
final class URLOpeningSpy: URLOpening {
    private(set) var openedURLs: [URL] = []
    var lastOpenedURL: URL? { openedURLs.last }
    func open(_ url: URL) { openedURLs.append(url) }
}
```

> **Diagnostic correction #2**: `OpenURLAction` has no `init()` — only
> `init(handler:)`. The `SystemURLOpener` takes an explicit `OpenURLAction`
> from the caller; there is no static default `OpenURLAction()`.
>
> **Diagnostic correction #3**: `URLOpeningSpy` is in `SingleThread/`, not
> `SingleThreadTests/`, so the UI-test process can reference it without
> a separate test bundle import. Unit tests access it via
> `@testable import SingleThread`.

#### 2. Unit tests for the contract
**File**: `SingleThreadTests/URLOpeningTests.swift`
**Action**: create

```swift
@testable import SingleThread
import SwiftUI
import Testing

@MainActor
struct URLOpeningTests {
    @Test
    func spyRecordsOpenedURL() {
        let spy = URLOpeningSpy()
        let url = URL(string: "x-apple-reminderkit://REMCDReminder/test")!
        spy.open(url)
        #expect(spy.lastOpenedURL?.absoluteString == "x-apple-reminderkit://REMCDReminder/test")
    }

    @Test
    func spyAccumulatesMultipleOpens() {
        let spy = URLOpeningSpy()
        spy.open(URL(string: "a://1")!)
        spy.open(URL(string: "a://2")!)
        #expect(spy.openedURLs.count == 2)
    }

    @Test
    func systemURLOpenerForwards() {
        let flag = URLFlag()
        let action = OpenURLAction(handler: { url in
            flag.opened = true
            flag.url = url
            return .handled
        })
        let opener = SystemURLOpener(action: action)
        let url = URL(string: "x-apple-reminderkit://REMCDReminder/E0B6FFFB")!
        opener.open(url)
        #expect(flag.opened)
        #expect(flag.url?.absoluteString == "x-apple-reminderkit://REMCDReminder/E0B6FFFB")
    }
}
```

> `URLFlag` is a tiny `@MainActor final class` with `var opened = false`
> and `var url: URL?` — defined in the test file. The handler runs
> synchronously on `@MainActor`, so the reference-type holder is safe
> without an external concurrency-extras dependency.

### Verification
#### Automated
- [x] `make test SIM='iPhone 17,OS=26.0'` passes for the new `URLOpeningTests` suite

#### Manual
- [ ] Build succeeds — `URLOpening` protocol compiles; spy compiles; tests compile

---

## Phase 2: `ContentViewModel` wiring

### Changes

#### 1. Add `urlOpener` property, `openInReminders(_:)` method, and update init
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

Three changes:

**a) Add stored property (after `let dictation`):**
```swift
let urlOpener: any URLOpening
```

**b) Update `init` to accept and store `urlOpener`:**
```swift
init(
    store: ReminderStore,
    backgroundImage: BackgroundImageStore,
    speechTranscriber: any SpeechTranscribing,
    showCompletionGlow: ShowCompletionGlowPreference = ShowCompletionGlowPreference(),
    urlOpener: (any URLOpening)? = nil) {
    self.store = store
    self.backgroundImage = backgroundImage
    self.showCompletionGlow = showCompletionGlow
    self.urlOpener = urlOpener ?? SystemURLOpener(
        action: OpenURLAction(handler: { _ in .handled }))
    dictation = DictationViewModel(speechTranscriber: speechTranscriber, store: store)
}
```

> Default is a no-op `SystemURLOpener` with an ignored handler so previews
> and test call sites that don't pass `urlOpener` compile unchanged.

**c) Add method (after the existing store-mutation-forwarding block, e.g. after `undoLastCompletion`):**
```swift
func openInReminders(_ reminder: EKReminder) {
    guard let url = ReminderDeepLink.url(
        forReminderIdentifier: reminder.calendarItemIdentifier)
    else { return }
    urlOpener.open(url)
}
```

#### 2. Unit tests for the new method
**File**: `SingleThreadTests/ContentViewModelTests.swift`
**Action**: create

```swift
@testable import SingleThread
import EventKit
import SingleThreadCore
import Testing

@MainActor
struct ContentViewModelTests {
    private static let store = EKEventStore()

    @Test
    func openInRemindersOpensCorrectURL() {
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Test"
        // EKReminder(eventStore:) assigns a UUID to calendarItemIdentifier
        // immediately, even before a save. Capture it for the assertion.
        let identifier = reminder.calendarItemIdentifier
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(reminder)

        let expected = "x-apple-reminderkit://REMCDReminder/\(identifier)"
        #expect(spy.lastOpenedURL?.absoluteString == expected)
    }

    @Test
    func openInRemindersWithEmptyIdentifierDoesNothing() {
        // This path is defensive — a real EKReminder always gets a UUID,
        // but the guard handles the edge case.
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        // Create a reminder but clear its identifier via KVC (the only way
        // to get an empty identifier since the property is readonly).
        let reminder = EKReminder(eventStore: Self.store)
        reminder.setValue("", forKey: "calendarItemIdentifier")
        viewModel.openInReminders(reminder)

        #expect(spy.openedURLs.isEmpty)
    }

    @Test
    func openInRemindersWithValidReminderRecordsURL() {
        // Sanity: a real freshly-created EKReminder has a UUID identifier,
        // and openInReminders passes it to the spy.
        let reminder = EKReminder(eventStore: Self.store)
        reminder.title = "Buy milk"
        let spy = URLOpeningSpy()
        let viewModel = ContentViewModel(
            store: ReminderStore(eventStore: InMemoryEventStore(), loadsReminders: false),
            backgroundImage: BackgroundImageStore(),
            speechTranscriber: ReminderDictation(),
            urlOpener: spy)

        viewModel.openInReminders(reminder)

        #expect(spy.openedURLs.count == 1)
        let urlString = spy.lastOpenedURL!.absoluteString
        #expect(urlString.hasPrefix("x-apple-reminderkit://REMCDReminder/"))
        // UUID portion should be 36 chars (dashed UUID format)
        let uuidPortion = String(urlString.dropFirst("x-apple-reminderkit://REMCDReminder/".count))
        #expect(uuidPortion.count == 36)
    }
}
```

> **Diagnostic correction #1**: `calendarItemIdentifier` is `readonly` and
> cannot be set via JSON seed or `makeReminder`. However, `EKReminder(eventStore:)`
> DOES assign a UUID immediately — confirmed by existing preview code using
> `mockReminder.calendarItemIdentifier` in `ContentView+Previews.swift:64`.
> The test creates a fresh `EKReminder`, reads its auto-assigned UUID, and
> asserts the spy URL matches.

### Verification
#### Automated
- [x] `make test SIM='iPhone 17,OS=26.0'` passes — Phase 1 tests + new `ContentViewModelTests`

#### Manual
- [ ] Build succeeds with updated `ContentViewModel` init (all existing call sites
  compile thanks to the default `nil` parameter)

---

## Phase 3: View wiring + production injection + UI-test seam

### Changes

#### 1. Replace context-menu button action
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Replace `ContentView.swift:408-413` (the context-menu "View in Reminders" button):

```swift
// OLD:
Button {
    let deepLink = ReminderDeepLink.url(
        forReminderIdentifier: reminder.calendarItemIdentifier)
    if let url = deepLink {
        openURL(url)
    }
} label: {
    Label("View in Reminders", systemImage: "eye")
}

// NEW:
Button {
    viewModel.openInReminders(reminder)
} label: {
    Label("View in Reminders", systemImage: "eye")
}
```

After the replacement, `@Environment(\.openURL)` is no longer used directly
in `ContentView`'s context menu. The declaration at `ContentView.swift:269-270`
can be removed if no other call site reads it — but there may be indirect
usage; verify by attempting to remove and checking compilation.

#### 2. UI-test spy seam in `contentViewModel`
**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

**a) Convert `contentViewModel` from a computed property to a method**
so it can optionally accept the environment's `OpenURLAction`:

```swift
// OLD (line 203-214):
var contentViewModel: ContentViewModel {
    let viewModel = ContentViewModel(
        store: store,
        backgroundImage: backgroundImage,
        speechTranscriber: ReminderDictation())
    if ProcessInfo.processInfo.arguments.contains("--ui-testing-glow") {
        viewModel.completionGlow.duration = 2.0
    }
    return viewModel
}

// NEW:
func makeContentViewModel(openURLAction: OpenURLAction? = nil) -> ContentViewModel {
    let urlOpener: any URLOpening
    if ProcessInfo.processInfo.arguments.contains("--url-opener-spy") {
        urlOpener = urlOpenerSpy ?? {
            let spy = URLOpeningSpy()
            urlOpenerSpy = spy
            return spy
        }()
    } else if let openURLAction {
        urlOpener = SystemURLOpener(action: openURLAction)
    } else {
        urlOpener = SystemURLOpener(
            action: OpenURLAction(handler: { _ in .handled }))
    }

    let viewModel = ContentViewModel(
        store: store,
        backgroundImage: backgroundImage,
        speechTranscriber: ReminderDictation(),
        urlOpener: urlOpener)
    if ProcessInfo.processInfo.arguments.contains("--ui-testing-glow") {
        viewModel.completionGlow.duration = 2.0
    }
    return viewModel
}

// Add stored property (after `let usesInMemoryStore`):
private var urlOpenerSpy: URLOpeningSpy?
```

> The `urlOpenerSpy` is stored so `ContentView` can read it back for the
> accessibility-element seam (see change #3 below). When `--url-opener-spy`
> is absent, `nil` acts as "use real/fresh opener" for production.
> In the spy path, reuse the same instance so the view and view model share
> one recording.

#### 3. Render spy URL as an accessibility element
**File**: `SingleThread/ContentView.swift`
**Action**: modify

**a) Add `@State` property** (in the `// MARK: Internal` section, near the
other `@State`/`@AppStorage` properties):

```swift
#if os(iOS)
    @State private var lastOpenedURL: String?
#endif
```

**b) Update the context-menu button action** to capture the spy URL after
calling `openInReminders` (replaces the old `openURL` call — see change #1):

```swift
Button {
    viewModel.openInReminders(reminder)
    if let spy = viewModel.urlOpener as? URLOpeningSpy {
        lastOpenedURL = spy.lastOpenedURL?.absoluteString
    }
} label: {
    Label("View in Reminders", systemImage: "eye")
}
```

> The `@State` mutation triggers a SwiftUI body re-evaluation, so the
> spy element renders immediately after the tap. The `openInReminders`
> method records the URL synchronously, so `spy.lastOpenedURL` is already
> set by the time we read it.

**c) Add the spy element** in the `body`, inside the `#if os(iOS)` block
that already contains the context menu (or at the end of the outermost
view, gated by `#if os(iOS)`). The exact placement: after the closing
`}` of the `List`/`ZStack` that contains the reminder card, but still
inside the iOS view hierarchy:

```swift
#if os(iOS)
    if ProcessInfo.processInfo.arguments.contains("--url-opener-spy"),
       let url = lastOpenedURL {
        Text("spyURL-\(url)")
            .opacity(0)
            .accessibilityIdentifier("lastOpenedURL")
            .accessibilityLabel("spyURL-\(url)")
    }
#endif
```

> The `accessibilityLabel` makes the URL readable via
> `staticTexts["lastOpenedURL"].label`. The accessibility identifier
> is `"lastOpenedURL"` and the label starts with `"spyURL-"` so the
> UI test can assert the prefix.

#### 4. Pass the production `OpenURLAction` from the scene
**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

```swift
// OLD:
var body: some Scene {
    WindowGroup {
        ContentView(viewModel: viewModel.contentViewModel, appViewModel: viewModel)
    }
}

// NEW:
@Environment(\.openURL) private var openURL

var body: some Scene {
    WindowGroup {
        ContentView(
            viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
            appViewModel: viewModel)
    }
}
```

This captures the system's `OpenURLAction` from the scene's environment and
passes it through `AppViewModel` → `SystemURLOpener` → `ContentViewModel`
→ `openInReminders`. The `--url-opener-spy` branch inside `makeContentViewModel`
takes precedence, so a UI-test launch with the spy arg ignores the scene's
action entirely (the spy records the URL without opening anything).

#### 5. Preview init overloads
**File**: `SingleThread/ContentView+Previews.swift`
**Action**: no changes needed

The two preview `init` overloads in `ContentView.swift` (lines 28-61) create
`ContentViewModel` with the default `urlOpener: nil`, which resolves to the
no-op `SystemURLOpener(handler: { _ in .handled })`. Existing previews compile
unchanged.

### Verification
#### Automated
- [ ] `make build SIM='iPhone 17,OS=26.0'` — compiles without errors
- [ ] `make format` — SwiftFormat passes
- [ ] `make lint` — SwiftLint passes (`--strict`) on the app target
- [ ] Full `./scripts/test.sh` — all unit tests + UI tests pass, no regressions

#### Manual
- [ ] Run app in simulator, long-press the reminder card, tap "View in Reminders" —
  Reminders app opens (same UX as before, now routed through the protocol)
- [ ] Check with `--url-opener-spy` launch arg: the spy records the URL, the
  hidden label renders, and no real URL open occurs (the spy absorbs the call)

---

## Phase 4: UI test — "View in Reminders" context menu

### Changes

#### 1. New UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify — add new test method after the existing
`testDeleteViaContextMenuRemovesReminder` (or at end of the Delete section)

```swift
@MainActor
func testViewInRemindersOpensURL() {
    let app = launchSeeded(
        #"{"reminders":[{"title":"Buy groceries"}]}"#,
        extra: ["--url-opener-spy"])

    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.staticTexts["Buy groceries"].press(forDuration: 1.0)

    let viewInReminders = app.buttons["View in Reminders"]
    XCTAssertTrue(
        viewInReminders.waitForExistence(timeout: 3),
        "Long-press should reveal the 'View in Reminders' context action")
    viewInReminders.tap()

    let spyLabel = app.staticTexts["lastOpenedURL"]
    XCTAssertTrue(spyLabel.waitForExistence(timeout: 3))
    XCTAssertTrue(
        spyLabel.label.hasPrefix("spyURL-x-apple-reminderkit://REMCDReminder/"),
        "Expected ReminderKit deep link prefix, got: \(spyLabel.label)")

    // The UUID portion should be 36 chars (dashed UUID).
    let fullURL = String(spyLabel.label.dropFirst("spyURL-".count))
    let uuidPart = String(fullURL.dropFirst("x-apple-reminderkit://REMCDReminder/".count))
    XCTAssertEqual(uuidPart.count, 36, "Expected dashed UUID (36 chars), got: \(uuidPart)")
}
```

> **Diagnostic correction #1 applied**: the test does NOT seed a
> `calendarItemIdentifier` in the JSON — the seeded reminder gets a UUID
> from `EKReminder(eventStore:)` on creation (inside `UITestingSeed.materialize()`).
> The test asserts only the scheme + path prefix plus UUID format (36 chars),
> not a specific hardcoded UUID.

### Verification
#### Automated
- [ ] `make ui-test SIM='iPhone 17,OS=26.0'` — new test passes alongside existing UI tests
- [ ] `./scripts/test.sh` — full gate passes (format + lint + build + unit + UI + Periphery)

#### Manual
- [ ] Run `make ui-test` and observe the test pass: context menu appears, tap,
  spy element found, URL prefix matches

---

## Testing Checkpoints (cumulative)

| Phase | What must be green | Command |
|-------|--------------------|---------|
| Phase 1 | `URLOpeningTests` (3 tests) | `xcodebuild test -project SingleThread.xcodeproj -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.0' -only-testing:SingleThreadTests/URLOpeningTests` |
| Phase 2 | Phase 1 + `ContentViewModelTests` (3 tests) | `xcodebuild test ... -only-testing:SingleThreadTests/URLOpeningTests -only-testing:SingleThreadTests/ContentViewModelTests` |
| Phase 3 | Full build + all existing tests | `./scripts/test.sh` |
| Phase 4 | Phase 3 + new UI test | `make ui-test SIM='iPhone 17,OS=26.0'` then `./scripts/test.sh` |

## Notes

- **`ReminderDeepLink` is not touched** — it stays as-is in
  `SingleThreadCore/Sources/SingleThreadCore/ReminderDeepLink.swift`.
- **`ReminderDisplay` stays identifier-free** — the DTO is unchanged.
- **No inbound URL scheme** — the app doesn't register any URL handler.
- **Fire-and-forget** — `openURL` result remains discarded; there is no failure
  alert or fallback.
- **`--url-opener-spy`** is a new launch arg alongside `--seed` and `--ui-testing`
  in the seam ecosystem. It is ONLY used in the UI test; production never uses it.
- **`OpenURLAction` has no `init()`** — always use `init(handler:)`. The no-op
  default is `OpenURLAction(handler: { _ in .handled })`.
- **`URLFlag` helper**: a `@MainActor final class` with `var opened` and
  `var url: URL?` properties — defined inline in the test file. No external
  dependency needed.