# Implementation Plan

## Overview

Make `http(s)://` and `www.`-prefixed URLs in a reminder's title and notes render as tappable links in the iOS/macOS app, opening via the existing injected `URLOpening`. The work refactors `CodeSpanFormatter.format` onto a public `segments(in:)` segmenter, adds a pure `LinkFormatter` in `SingleThreadCore`, and wires `ReminderCardView` + `ReminderDisplayRow` to new `titleAttributedWithLinks` / `notesAttributedWithLinks` accessors with accessibility custom actions and localized labels. Widget and watch stay on the code-span-only accessors.

**Recon findings that constrain the plan** (from `.pi/skills/ai-sorting` and repo AGENTS.md):

- `SingleThreadCore` does **not** enable `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — everything new there is explicitly `nonisolated`.
- Unit tests are Swift Testing (`@Test`); names must **not** start with `test`/`testing` (SwiftFormat renames them). UI tests are XCTest and keep `test…`.
- The scene already reads `@Environment(\.openURL)` at `SingleThreadApp` level and threads it into `makeContentViewModel`; the installed `OpenURLAction` must be added **inside** the `WindowGroup` content so the App-level `openURL` (the captured original) is unaffected — that is what prevents recursion.
- `ReminderDisplayRow` currently renders plain `Text(display.title)` (not `titleAttributed`); adopting `titleAttributedWithLinks` is the intended (ticket-scoped) upgrade and also gives it code-span styling.
- There is **no** existing UI test for `--url-opener-spy`; nothing currently surfaces a link-tap through the spy except `ContentView`'s iOS overlay, which is only populated by the context-menu path. Phase 5 must add a minimal spy-read seam or be dropped (ticket calls it best-effort).
- The Core catalog localization tests are generic (`catalogsHaveAllSixLanguages`, `nonEnglishValuesDifferFromEnglish`) — no `requiredKeys` fixture to register.

No schema, migration, persisted-format, new-subsystem, or dependency changes. No open questions.

---

## Phase 1: `CodeSpanFormatter` segmenter (pure refactor)

Walking skeleton: extract the existing scanning loop into `segments(in:)` and rebuild `format(_:)` on top of it. Behaviour must be byte-for-byte identical; all existing `CodeSpanFormatterTests` stay green unchanged.

### Changes

#### 1. Segmenter

**File**: `SingleThreadCore/Sources/SingleThreadCore/CodeSpanFormatter.swift`
**Action**: modify

Add a public `Segment` type and `segments(in:)`, and rewrite `format(_:)` to consume it. The extraction is mechanical: the current loop's `pendingPlain` is the `.plain` bucket and each `codeSpan.content` is a `.code` segment.

```swift
public nonisolated enum CodeSpanFormatter {
    public enum Segment: Equatable, Sendable {
        case plain(String)
        case code(String)
    }

    /// Splits `text` into plain and backtick-delimited code segments.
    /// Fences are stripped; unmatched/double backticks stay literal plain text.
    public static func segments(in text: String) -> [Segment] {
        var segments: [Segment] = []
        var remainder = text[...]
        var pendingPlain = ""

        while !remainder.isEmpty {
            guard let nextFence = remainder.firstIndex(of: "`") else {
                pendingPlain.append(contentsOf: remainder)
                break
            }
            pendingPlain.append(contentsOf: remainder[..<nextFence])
            remainder = remainder[nextFence...]

            guard let codeSpan = extractCodeSpan(from: remainder) else {
                pendingPlain.append("`")
                remainder = remainder.dropFirst()
                continue
            }
            if !pendingPlain.isEmpty {
                segments.append(.plain(pendingPlain))
                pendingPlain = ""
            }
            segments.append(.code(codeSpan.content))
            remainder = codeSpan.remainder
        }
        if !pendingPlain.isEmpty {
            segments.append(.plain(pendingPlain))
        }
        return segments
    }

    public static func format(_ text: String) -> AttributedString {
        var result = AttributedString()
        for segment in segments(in: text) {
            switch segment {
            case .plain(let plain):
                result.append(AttributedString(plain))
            case .code(let content):
                var code = AttributedString(content)
                applyCodeAttributes(to: &code)
                result.append(code)
            }
        }
        return result
    }

    // ...
    static func applyCodeAttributes(to attributed: inout AttributedString) { // was `private`
```

`extractCodeSpan` / `extractFenced` / `extractInline` / `CodeSpan` / `platformSecondaryBackground` stay `private` and unchanged.

#### 2. Segmenter tests

**File**: `SingleThreadTests/CodeSpanFormatterTests.swift`
**Action**: modify

Add table-driven `@Test`s (no `test` prefix) alongside the existing ones:

- `segmentsSplitPlainAndInlineCode` — `"a `b` c"` → `[.plain("a "), .code("b"), .plain(" c")]`
- `segmentsPreserveFencedCode` — `"```x```"` → `[.code("x")]`; unclosed fence → `[.plain("a "), .code("rest")]`
- `segmentsTreatLiteralBackticksAsPlainText` — double backtick and unmatched single backtick both stay inside a `.plain`
- `segmentsEmptyTextYieldsNoSegments` — `""` → `[]`
- `formatPreservesCodeStylingFromSegments` — a sanity assertion that `format` output for `"a `b`"` has the `.backgroundColor` on the code run

### Verification

#### Automated

- [x] `make format` then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadTests/CodeSpanFormatterTests` passes (exit 0, non-zero case count)
- [x] `SIM=CDE2B125-A88D-4A3F-BE9D-A09965617C60 scripts/test-one.sh SingleThreadTests` compiles the package

#### Manual

- [ ] Confirm no existing `CodeSpanFormatterTests` assertion text changed in the diff (pure refactor)

---

## Phase 2: `LinkFormatter` detection + attributed string

New pure type in `SingleThreadCore` that links URLs in `.plain` segments only. This phase ships the full detection rule set with table-driven tests; no view changes yet.

### Changes

#### 1. `LinkFormatter`

**File**: `SingleThreadCore/Sources/SingleThreadCore/LinkFormatter.swift`
**Action**: create

```swift
import Foundation
#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Detects `http(s)://` and `www.`-prefixed links in plain text and builds the
/// link-styled `AttributedString`. Backtick code spans keep code styling and
/// are never linked.
public nonisolated enum LinkFormatter {
    /// Text with code spans styled and URLs carrying a `.link` attribute plus
    /// explicit accent foreground (no underline), so notes stay deterministic
    /// under `.foregroundStyle(.secondary)`.
    public static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        for segment in CodeSpanFormatter.segments(in: text) {
            switch segment {
            case .code(let content):
                var code = AttributedString(content)
                CodeSpanFormatter.applyCodeAttributes(to: &code)
                result.append(code)
            case .plain(let plain):
                result.append(plainAttributed(plain))
            }
        }
        return result
    }

    /// Normalised URLs in document order — drives the accessibility custom actions.
    public static func links(in text: String) -> [URL] {
        CodeSpanFormatter.segments(in: text).flatMap { segment in
            switch segment {
            case .code: []
            case .plain(let plain): detect(in: plain).map(\.url)
            }
        }
    }

    // MARK: Private

    private struct DetectedLink {
        let range: Range<String.Index>
        let url: URL
    }

    /// RFC 3986 unreserved + reserved + `%`. Any other scalar (whitespace, CJK,
    /// quotes) terminates the token.
    private static let urlCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")

    private static let prefixCandidates = ["http://", "https://", "www."]

    private static func detect(in plain: String) -> [DetectedLink] {
        var links: [DetectedLink] = []
        var searchStart = plain.startIndex
        while searchStart < plain.endIndex {
            guard let candidate = nextPrefix(in: plain, from: searchStart) else { break }
            var tokenEnd = candidate.start
            while tokenEnd < plain.endIndex,
                  let scalar = plain[tokenEnd].unicodeScalars.first,
                  urlCharacters.contains(scalar) {
                tokenEnd = plain.index(after: tokenEnd)
            }
            let token = String(plain[candidate.start..<tokenEnd])
            let trimmed = trimTrailingPunctuation(token)
            if let url = normalise(trimmed, prefixedWithWWW: candidate.isWWW) {
                let end = plain.index(candidate.start, offsetBy: trimmed.count)
                links.append(DetectedLink(range: candidate.start..<end, url: url))
            }
            searchStart = tokenEnd
        }
        return links
    }

    /// Earliest `http://` / `https://` / `www.` at or after `start`, case-insensitive.
    private static func nextPrefix(
        in plain: String,
        from start: String.Index) -> (start: String.Index, isWWW: Bool)? {
        var best: (start: String.Index, isWWW: Bool)?
        for prefix in prefixCandidates {
            guard let range = plain.range(
                of: prefix, options: .caseInsensitive, range: start..<plain.endIndex) else { continue }
            if let best, range.lowerBound >= best.start { continue }
            best = (range.lowerBound, prefix == "www.")
        }
        return best
    }

    private static func normalise(_ token: String, prefixedWithWWW: Bool) -> URL? {
        if prefixedWithWWW {
            guard token.count > 4 else { return nil } // "www." + ≥1 char
            return URL(string: "https://" + token)
        }
        guard let schemeEnd = token.range(of: "://") else { return nil }
        let scheme = token[..<schemeEnd.lowerBound].lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        let rest = token[schemeEnd.lowerBound...]
        guard rest.count > 3 else { return nil } // "://" + ≥1 char
        return URL(string: scheme + rest)
    }

    private static let alwaysTrimmed: Set<Character> = [".", ",", ";", ":", "!", "?"]
    private static let bracketPairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// Drops trailing `.,;:!?` always, and `)]}` only when its opening bracket
    /// is outnumbered inside the token (keeps `…/Foo_(bar)`).
    private static func trimTrailingPunctuation(_ token: String) -> String {
        var characters = Array(token)
        while let last = characters.last {
            if alwaysTrimmed.contains(last) {
                characters.removeLast()
                continue
            }
            if let opener = bracketPairs[last],
               characters.filter({ $0 == opener }).count < characters.filter({ $0 == last }).count {
                characters.removeLast()
                continue
            }
            break
        }
        return String(characters)
    }

    private static func plainAttributed(_ plain: String) -> AttributedString {
        var result = AttributedString()
        var cursor = plain.startIndex
        for link in detect(in: plain) {
            if cursor < link.range.lowerBound {
                result.append(AttributedString(String(plain[cursor..<link.range.lowerBound])))
            }
            var run = AttributedString(String(plain[link.range]))
            run.link = link.url
            #if canImport(SwiftUI)
                run.foregroundColor = .accentColor
                run.underlineStyle = nil
            #endif
            result.append(run)
            cursor = link.range.upperBound
        }
        if cursor < plain.endIndex {
            result.append(AttributedString(String(plain[cursor...])))
        }
        return result
    }
}
```

If `run.underlineStyle = nil` does not compile against the SwiftUI attribute scope, use `run.underlineStyle = Text.LineStyle()` instead — the observable requirement is "no underline".

#### 2. Tests

**File**: `SingleThreadTests/LinkFormatterTests.swift`
**Action**: create

Swift Testing `@Test`, table-driven (`@Test(arguments:)`) where the rule set is a list of `(input, expectedURL)` pairs. Cover **all** detection rules, happy and sad:

- `detectsExplicitHTTPAndHTTPSLinks` — both schemes, multiple links in one string, URLs returned in order from `links(in:)`
- `normalisesWWWWithoutScheme` — `www.example.com` → `https://www.example.com`
- `schemeMatchingIsCaseInsensitive` — `HTTP://Example.com` → `http://Example.com`
- `ignoresBareDomainsEmailsAndPhoneNumbers` — `example.com`, `a@b.com`, `+1 555 0100` produce no link
- `stopsLinksAtNonURLCharacters` — `https://x.comを参照` → only `https://x.com`
- `stripsTrailingUnbalancedPunctuation` — `(https://x.com)` / `https://x.com).` → `https://x.com`
- `keepsBalancedBracketPunctuation` — `https://en.wikipedia.org/wiki/Foo_(bar)` unchanged
- `doesNotLinkInsideCodeSpans` — `` `https://x.com` `` yields no link, and `.code` styling is preserved
- `malformedSchemeOnlyIsNotALink` — `http://` alone, `www.` alone
- `appliesLinkAttributeToLinkRunsOnly` — traverse `attributed("see https://x.com now")` runs; the URL run has `.link` set and the surrounding runs do not

### Verification

#### Automated

- [x] `make format` then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadTests/LinkFormatterTests` passes (non-zero case count)
- [x] `scripts/test-one.sh SingleThreadTests/CodeSpanFormatterTests` still passes

#### Manual

- [ ] Spot-check `links(in:)` against the ticket's rule list (localhost/IP hosts with a scheme match; bare domains do not)

---

## Phase 3: Wire links into the app end-to-end

`ReminderDisplay` gains the link-bearing accessors, the card and row adopt them, and the scene installs the `OpenURLAction` that routes inline `Text` taps through the injected `URLOpening`. After this phase the feature works at runtime (without custom actions / localization).

### Changes

#### 1. `ReminderDisplay` accessors

**File**: `SingleThreadCore/Sources/SingleThreadCore/ReminderDisplay.swift`
**Action**: modify

Append next to the existing `titleAttributed` / `notesAttributed`, which stay unchanged (widget + watch keep using them):

```swift
/// `title` with code spans styled and URLs link-attributed.
public var titleAttributedWithLinks: AttributedString {
    LinkFormatter.attributed(title)
}

/// `notes` with code spans styled and URLs link-attributed, or `nil` when raw
/// notes is `nil`.
public var notesAttributedWithLinks: AttributedString? {
    guard let notes else { return nil }
    return LinkFormatter.attributed(notes)
}
```

#### 2. Card and row adopt

**Files**: `SingleThread/ReminderCardView.swift`, `SingleThread/ReminderDisplayRow.swift`
**Action**: modify

- `ReminderCardView.content` (`SingleThread/ReminderCardView.swift:97`, `:133`): `Text(display.titleAttributed)` → `Text(display.titleAttributedWithLinks)`; `if let notesAttr = display.notesAttributed` → `display.notesAttributedWithLinks`. Keep `.font(.title)` / `.font(.callout)` / `.foregroundStyle(.secondary)` / `.lineLimit(3)` as-is.
- `ReminderDisplayRow.body` (`SingleThread/ReminderDisplayRow.swift:17`): `Text(display.title)` → `Text(display.titleAttributedWithLinks)`. Keep `.font(font)`.
- **Do not touch** `SingleThreadWidget/NextThingWidget.swift:193,219` or `SingleThreadWatch/WatchReminderView.swift:334,357` — they stay on `titleAttributed` / `notesAttributed`.

#### 3. Resolve the opener once, install the scene action

**File**: `SingleThread/AppViewModel.swift`
**Action**: modify

Extract the opener-selection block out of `makeContentViewModel` (`SingleThread/AppViewModel.swift:167-190`) into a reusable resolver so the scene forwards to the exact same instance (spy reuse stays intact):

```swift
/// Resolves the opener shared by the "View in Reminders" deep link and inline
/// link taps. Under `--url-opener-spy` the shared spy is reused (stored back so
/// the view can read the last URL); otherwise the scene's live `OpenURLAction`
/// is wrapped, with a no-op fallback.
func resolvedURLOpening(openURLAction: OpenURLAction? = nil) -> any URLOpening {
    if isURLSpyUITesting {
        if let spy = urlOpenerSpy { return spy }
        let freshSpy = URLOpeningSpy()
        urlOpenerSpy = freshSpy
        return freshSpy
    }
    if let openURLAction {
        return SystemURLOpener(action: openURLAction)
    }
    return SystemURLOpener.noop
}
```

`makeContentViewModel` becomes `let urlOpener = resolvedURLOpening(openURLAction: openURLAction)` followed by the existing `ContentViewModel(...)` construction.

**File**: `SingleThread/SingleThreadApp.swift`
**Action**: modify

Install the forwarding action **inside** the `WindowGroup` content, alongside the existing `.environment(\.locale, …)`:

```swift
ContentView(
    viewModel: viewModel.makeContentViewModel(openURLAction: openURL),
    appViewModel: viewModel)
    .environment(\.openURL, linkOpenURLAction)
    .environment(\.locale, AppLocaleState.current.effectiveLocale)
```

```swift
/// Routes inline `Text` link taps through the same injectable opener the deep
/// link uses, so `--url-opener-spy` records them. `openURL` here is the action
/// installed *above* this App (read at App level, so unaffected by the modifier
/// below); `SystemURLOpener` wraps that captured original, which is what would
/// recurse if we forwarded to the newly installed action instead.
private var linkOpenURLAction: OpenURLAction {
    let original = openURL
    return OpenURLAction { url in
        viewModel.resolvedURLOpening(openURLAction: original).open(url)
        return .handled
    }
}
```

#### 4. Tests

**File**: `SingleThreadTests/ReminderDisplayTests.swift`
**Action**: modify

- `titleAttributedWithLinksLinksURLs` — a `ReminderDisplay(title: "See https://example.com")` yields a `.link` run with `https://example.com`
- `titleAttributedWithLinksPreservesCodeSpans` — `` `https://x.com` `` yields no `.link` run
- `notesAttributedWithLinksIsNilWhenNotesMissing` — `nil` notes → `nil`; non-nil notes with `www.example.com` yields `https://www.example.com`

### Verification

#### Automated

- [x] `make format` then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadTests/ReminderDisplayTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/LinkFormatterTests` and `…/CodeSpanFormatterTests` still pass
- [x] `make build` succeeds (card/row/scene compile, no source-located warnings)

#### Manual

- [ ] Launch the app against a seeded reminder with a URL in its title; tap the link and confirm the browser opens
- [ ] Confirm the widget and watch render URLs as plain text (no link affordance)

---

## Phase 4: Accessibility custom actions + localization

### Changes

#### 1. Localized label

**File**: `SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift`
**Action**: modify

```swift
/// Accessibility action label for a detected link, interpolated with the
/// link's host. "Open link to %@".
public static func openLink(to host: String) -> LocalizedStringResource {
    LocalizedStringResource("Open link to \(host)", table: "Localizable", bundle: .module)
}
```

#### 2. Catalog entry (all six languages)

**File**: `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings`
**Action**: modify

Insert a new key inside `"strings"`, anchored on the first entry (use `edit` with the small anchor `"strings": {` and keep the existing `"%@ priority"` entry below it):

```json
"Open link to %@": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "Open link to %@" } },
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "打开链接 %1$@" } },
    "es": { "stringUnit": { "state": "translated", "value": "Abrir enlace a %1$@" } },
    "ja": { "stringUnit": { "state": "translated", "value": "%1$@ へのリンクを開く" } },
    "de": { "stringUnit": { "state": "translated", "value": "Link zu %1$@ öffnen" } },
    "fr": { "stringUnit": { "state": "translated", "value": "Ouvrir le lien vers %1$@" } }
  }
},
```

Match the surrounding file's existing indentation/formatting; every non-English value must differ from English (the existing `nonEnglishValuesDifferFromEnglish` test enforces this).

#### 3. Card custom actions

**File**: `SingleThread/ReminderCardView.swift`
**Action**: modify

Add the environment action and a derived link list, then attach one custom action per detected link to the already-combined `content` element (after the existing `.accessibilityElement(children: .combine)` at `ReminderCardView.swift:145`):

```swift
@Environment(\.openURL) private var openURL

/// Every link in the card's title and notes, in reading order.
private var linkURLs: [URL] {
    var urls = LinkFormatter.links(in: display.title)
    if let notes = display.notes {
        urls.append(contentsOf: LinkFormatter.links(in: notes))
    }
    return urls
}
```

```swift
.accessibilityElement(children: .combine)
.accessibilityCustomActions {
    ForEach(linkURLs, id: \.absoluteString) { url in
        AccessibilityAction(named: Text(SharedStrings.openLink(to: url.host() ?? url.absoluteString))) {
            openURL(url)
        }
    }
}
```

The `openURL(url)` call routes through the scene-installed action from Phase 3, so `--url-opener-spy` records it. `.combine` is kept — do not replace it.

#### 4. Tests

- [x] Generic localization tests cover the new key (`catalogsHaveAllSixLanguages`, `nonEnglishValuesDifferFromEnglish`) — no fixture change needed.
- [x] If compiler/API availability allows, add a unit test in `SingleThreadTests/LinkFormatterTests.swift` asserting `links(in: "a https://one.com b www.two.com")` returns `[https://one.com, https://www.two.com]` in order (backs the custom-action list).

### Verification

#### Automated

- [x] `make format` then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadTests/LocalizationTests` passes
- [x] `scripts/test-one.sh SingleThreadTests/LinkFormatterTests` passes
- [x] `scripts/test-one.sh SingleThreadTests` compiles the card changes
- [x] `scripts/check-appgroup-notify.sh` passes (unaffected but cheap)

#### Manual

- [ ] With VoiceOver, focus the card; the rotor lists one "Open link to <host>" action per link and invoking it opens the URL
- [ ] Switch the app language to each of de/es/fr/ja/zh-Hans and confirm the action label changes

---

## Phase 5: Best-effort UI test + manual verification doc

Per the ticket, the inline-tap UI test is **best-effort**. Inline links are not addressable in the accessibility tree, and `--url-opener-spy` currently surfaces its last URL only via `ContentView`'s iOS overlay, which is populated by the context-menu path. This phase adds a minimal spy-read seam, attempts the test, and drops both if the coordinate tap proves unreliable — documenting whichever path was taken.

### Changes

#### 1. Spy-read seam (iOS, test-only)

**File**: `SingleThread/ContentView.swift`
**Action**: modify

Under the existing `#if os(iOS)` spy overlay block, poll the shared spy so a link tap (which never touches `lastOpenedURL` today) becomes observable:

```swift
.task {
    guard isURLSpyUITesting else { return }
    while !Task.isCancelled {
        lastOpenedURL = viewModel.lastOpenedURLForUITesting ?? lastOpenedURL
        try? await Task.sleep(for: .milliseconds(100))
    }
}
```

`viewModel.lastOpenedURLForUITesting` reads the same `URLOpeningSpy` instance the scene forwarding action writes to (`AppViewModel.urlOpenerSpy` is reused by `resolvedURLOpening`), so the overlay's `accessibilityIdentifier("lastOpenedURL")` reflects link taps.

#### 2. UI test

**File**: `SingleThreadUITests/SingleThreadUITests.swift`
**Action**: modify

Add `@MainActor func testLinkTapRoutesThroughURLOpenerSpy()` (XCTest keeps the `test` prefix; UI tests are SwiftFormat-excluded). Space-free seed JSON, a link in the title:

```swift
let app = XCUIApplication()
app.launchArguments = [
    "--seed",
    "{\"reminders\":[{\"title\":\"See:https://example.com/path\",\"priority\":5}],\"calendars\":[\"Groceries\"],\"isEntitled\":true}",
    "--url-opener-spy",
    "--ui-testing-noop-settle"
]
app.launch()

let card = app.descendants(matching: .any)["reminderCard"].firstMatch
XCTAssertTrue(card.waitForExistence(timeout: 5))
// Inline links are not in the accessibility tree — tap inside the title region.
card.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()

let spy = app.descendants(matching: .any)["lastOpenedURL"].firstMatch
XCTAssertTrue(spy.waitForExistence(timeout: 5))
XCTAssertEqual(spy.label, "spyURL-https://example.com/path")
```

**Fallback rule (decide here, do not leave open):** run the test twice; if the coordinate tap misses or the spy label is wrong/flaky, **delete the test method and the `.task` seam from step 1**, and record in the manual doc + PR that the unit-tests-plus-manual path was taken. Unit tests in Phases 2–4 already cover detection and attribute construction; only the SwiftUI env-routing step is dropped.

#### 3. Manual verification doc

**File**: `docs/SimulatorManualVerification.md`
**Action**: modify

Append a section following the existing heading style (e.g. after `## Activation log hook` / near `## make simverify`):

```markdown
## Tappable links (VAR-1112)

1. Launch the app with a reminder whose title contains `https://example.com`
   and whose notes contain `www.apple.com` (use `--seed`, or type them in).
2. Tap the URL in the title — the default browser opens `https://example.com`.
3. Tap `www.apple.com` in the notes — it opens `https://www.apple.com`.
4. Confirm `daily.com` (bare domain) and `a@b.com` render as plain text.
5. Confirm a URL inside backticks stays code-styled and is not tappable.
6. Confirm the widget and watch show URLs as plain text.
```

### Verification

#### Automated

- [x] `make format` (never formats `SingleThreadUITests`) then `make lint` pass
- [x] `scripts/test-one.sh SingleThreadUITests/SingleThreadUITests/testLinkTapRoutesThroughURLOpenerSpy` passes twice; otherwise the fallback rule above was applied and the deletion documented
- [ ] Full gate `./scripts/test.sh` passes (run once via the `run-gate` skill)

#### Manual

- [ ] The six manual steps above pass on the pinned iOS simulator
- [ ] `docs/SimulatorManualVerification.md` renders the new section with correct code spans

---

## Final checks (after all phases)

- [x] `titleAttributed` / `notesAttributed` are still referenced by `NextThingWidget` and `WatchReminderView`; no link affordance added there
- [x] `ReminderCardView` uses `titleAttributedWithLinks` and `notesAttributedWithLinks`; `ReminderDisplayRow` uses `titleAttributedWithLinks` only (it never renders notes)
- [x] `AccessibilityAction` label `"Open link to %@"` resolves in all six languages
- [ ] `./scripts/test.sh` green (once, via `run-gate`)
- [ ] PR notes the UI-test path taken (kept or dropped) and why
