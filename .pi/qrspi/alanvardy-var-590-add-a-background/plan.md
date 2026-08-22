# Implementation Plan

## Overview

The main reminder list renders over a nature photograph (fetched from
`https://vardy.cc/unsplash`, persisted to Application Support) at 50% opacity,
refreshed hourly at launch, silently retaining the last good photo on failure;
Settings gains a hide-only "Background" toggle (default ON) and an attribution
footer "Photo by {photographer} on Unsplash" driven by the same stored
metadata. Watch/widget/App Group are untouched.

---

## Phase 1: Fetch, persist, and render

### Changes

#### 1. Network client seam
**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: create

```swift
import Foundation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif
import OSLog

/// Abstraction over the network transport so unit tests can inject a fake.
/// Named `fetchData` (not `data`) so the URLSession conformance below can wrap
/// the built-in `data(from:)` with HTTP-status validation — URLSession's own
/// async `data(from:)` does NOT throw on non-2xx responses.
protocol BackgroundImageFetching: AnyObject {
    func fetchData(from url: URL) async throws -> Data
}

extension URLSession: BackgroundImageFetching {
    func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

#### 2. Store
**File**: `SingleThread/BackgroundImageStore.swift` (same file)
**Action**: append

```swift
/// Sidecar metadata persisted next to the photo bytes. One write covers both
/// the displayed photo and the attribution credit, so they can never disagree.
private struct BackgroundMetadata: Codable {
    let photographer: String
    let fetchedAt: Date
}

/// Shape of the `GET https://vardy.cc/unsplash` JSON payload (`created_at` ignored).
private struct UnsplashPayload: Decodable {
    let url: URL
    let photographer: String
}

/// Fetches, persists, and serves the background photograph.
/// Phone-local cosmetic concern: never touches the App Group or sync payloads.
@MainActor
@Observable
final class BackgroundImageStore {
    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread", category: "BackgroundImage")

    /// Bytes of the currently-displayed photo, or nil before first success.
    private(set) var imageData: Data?
    /// Photographer of the currently-displayed photo, or nil.
    private(set) var photographer: String?

    private let client: any BackgroundImageFetching
    private let directory: URL

    private var imageURL: URL { directory.appendingPathComponent("background.jpg") }
    private var metadataURL: URL { directory.appendingPathComponent("background.json") }

    /// - Parameters:
    ///   - client: network transport; production default is `URLSession.shared`.
    ///   - directory: persistence location; tests inject a UUID temp directory.
    init(client: any BackgroundImageFetching = URLSession.shared, directory: URL? = nil) {
        self.client = client
        self.directory = directory ?? Self.defaultDirectory
    }

    private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SingleThread", isDirectory: true)
    }

    /// Loads stored bytes into observable state, then refetches over the
    /// network when the sidecar is missing/corrupt/stale. Called from
    /// ContentView's `.task`; rendering is never gated on the network result.
    /// Failure convention: persist to disk FIRST, then flip observable state;
    /// on any error, log and keep prior state.
    func refreshIfNeeded(maxAge: TimeInterval) async {
        loadStoredImage()
        guard !isFresh(maxAge: maxAge) else { return }
        do {
            let payloadData = try await client.fetchData(from: Self.endpoint)
            let payload = try JSONDecoder().decode(UnsplashPayload.self, from: payloadData)
            let data = try await client.fetchData(from: payload.url)
            guard isDecodableImage(data) else { throw URLError(.cannotDecodeContentData) }
            let metadata = BackgroundMetadata(
                photographer: payload.photographer, fetchedAt: Date())
            try persist(imageData: data, metadata: metadata) // disk before state
            imageData = data
            photographer = payload.photographer
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private

    /// Missing/corrupt sidecar ⇒ treated as "no valid stored image".
    private func loadStoredImage() {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(BackgroundMetadata.self, from: metadataData),
              let data = try? Data(contentsOf: imageURL),
              isDecodableImage(data)
        else {
            imageData = nil
            photographer = nil
            return
        }
        imageData = data
        photographer = metadata.photographer
    }

    private func isFresh(maxAge: TimeInterval) -> Bool {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(BackgroundMetadata.self, from: metadataData)
        else { return false }
        return Date().timeIntervalSince(metadata.fetchedAt) < maxAge
    }

    private func isDecodableImage(_ data: Data) -> Bool {
        #if os(iOS)
            UIImage(data: data) != nil
        #elseif os(macOS)
            NSImage(data: data) != nil
        #endif
    }

    /// Creates the directory if needed and writes both files atomically.
    private func persist(imageData: Data, metadata: BackgroundMetadata) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        try imageData.write(to: imageURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }
}
```

Decoder note: mirror the ISO8601 encoding with
`decoder.dateDecodingStrategy = .iso8601` in `loadStoredImage`/`isFresh`.

#### 3. Render layer + wiring
**File**: `SingleThread/ContentView.swift`
**Action**: modify

a) All three inits gain an injected-store parameter (default = production
store, so existing call sites/previews compile unchanged):

```swift
init(
    store: ReminderStore,
    speechTranscriber: (any SpeechTranscribing)? = nil,
    backgroundImage: BackgroundImageStore = BackgroundImageStore())
```

Same parameter appended to the `init(loadsReminders:...)` and pre-populated
convenience init; each assigns `self.backgroundImage = backgroundImage`.

b) Property (near `private let store`, with `StateObject`-like semantics —
plain `let`, since the store is created before view init):

```swift
var backgroundImage: BackgroundImageStore
```

c) ZStack gains the image child **between** `Color.systemBackground` and the
content branches (iOS only — the photo feature is iPhone/iPad scoped):

```swift
ZStack {
    Color.systemBackground.ignoresSafeArea()
    #if os(iOS)
        if let imageData = backgroundImage.imageData {
            Image(uiImage: UIImage(data: imageData)!)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.5)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    #endif
    if store.loadsReminders { ... }
}
```

Note: `imageData` is only ever set after `isDecodableImage` passed, so the
force-unwrap here is safe; alternatively bind `UIImage(data:)` in the `if`.
`.allowsHitTesting(false)` keeps the full-bleed decorative layer from
intercepting touches; `.accessibilityHidden(true)` marks it decorative.

d) `.task` block extended (alongside `store.start()`):

```swift
.task {
    store.showsUndatedReminders = showUndatedReminders
    await store.start()
    await backgroundImage.refreshIfNeeded(maxAge: 3600)
}
```

#### 4. Store unit tests
**File**: `SingleThreadTests/BackgroundImageStoreTests.swift`
**Action**: create (Swift Testing, `@MainActor @Suite(.serialized)`)

Recording fake + helpers:

```swift
private final class FakeBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    var stubbedData: [URL: Result<Data, Error>] = [:]

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return try stubbedData[url]!.get()
    }
}
```

Each test builds a store with a fresh `FileManager.default.temporaryDirectory
.appendingPathComponent(UUID().uuidString)` and a `1×1` JPEG constant
(`Data` base64 of a tiny JPEG, defined once as a fixture).

Tests to write:
- `successfulFetchStoresBytesAndMetadata` — stub JSON payload (real tiny JSON
  with `url` pointing at the image URL) + image bytes → `imageData` equals
  stubbed bytes, `photographer` matches; `background.jpg` and
  `background.json` exist on disk with matching contents.
- `nonImagePayloadRejected` — stub junk `Data` for the image URL → `imageData`
  stays nil, nothing written to disk.
- `failedFetchRetainsPriorImage` — pre-persist via a first successful fetch,
  then point the fake's image result at a thrown error and call
  `refreshIfNeeded` again → previous `imageData`/`photographer` unchanged.
- `staleSidecarTriggersRefetch` — successful fetch, then rewrite sidecar with
  `fetchedAt` older than `maxAge`, call again → fake saw ≥ 2 requests for the
  endpoint.
- `freshSidecarSkipsNetwork` — successful fetch, immediate second
  `refreshIfNeeded(maxAge: 3600)` → fake request count unchanged.
- `corruptOrMissingSidecarTreatedAsNoImage` — write `background.jpg` only (no
  sidecar) → `imageData` nil after `refreshIfNeeded`.

### Verification

#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes, including the six new `BackgroundImageStoreTests` cases
- [x] Fake-client paths covered: success / non-image rejection / failure retention / stale refetch / fresh skip

#### Manual
- [ ] Launch on iPhone 17 sim (light mode): photo fades in over systemBackground behind the list, ~50% opacity, full-bleed under safe areas; gear and cards remain tappable
- [ ] Repeat in dark mode: photo still visible against dark systemBackground, text readable
- [ ] Fresh install before first success: screen looks exactly as today (plain background), no spinner, no error UI
- [ ] `Application Support/SingleThread/` contains `background.jpg` + `background.json` after first success

---

## Phase 2: Settings "Background" toggle

### Changes

#### 1. ContentView toggle + conditional layer
**File**: `SingleThread/ContentView.swift`
**Action**: modify

a) New `@AppStorage` next to `showMicrophoneButton`:

```swift
@AppStorage("backgroundEnabled", store: .standard)
private var backgroundEnabled = true
```

b) Image-layer condition becomes (Phase 1's `if let` grows one clause):

```swift
if backgroundEnabled, let imageData = backgroundImage.imageData { ... }
```

c) Both `SettingsView(...)` constructions in `.sheet` (iOS and `#else` macOS
branches) gain:

```swift
backgroundEnabled: $backgroundEnabled,
```

#### 2. SettingsView toggle row
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

a) Both inits (iOS `#if os(iOS)` and `#else`) gain
`backgroundEnabled: Binding<Bool>` parameter, assigned `_backgroundEnabled =
backgroundEnabled`.

b) Stored property: `@Binding private var backgroundEnabled: Bool`.

c) New Toggle row immediately after the `showMicrophoneButton` Toggle
(same precedent):

```swift
Toggle(isOn: $backgroundEnabled) {
    Label("Background", systemImage: "photo")
}
```

d) Both `#Preview` blocks gain `backgroundEnabled: .constant(true)`.

#### 3. Seed reset
**File**: `SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift`
**Action**: modify

Add `"backgroundEnabled"` to `persistedKeys` (removed from both suites by
`resetPersistedState()` — harmless for App Group, required for `.standard`).

#### 4. Seed unit test
**File**: `SingleThreadTests/UITestingSeedTests.swift`
**Action**: modify

New test proving the key is cleared:

```swift
@Test
func resetPersistedStateClearsBackgroundEnabled() {
    UserDefaults.standard.set(false, forKey: "backgroundEnabled")
    UITestingSeed.resetPersistedState()
    #expect(UserDefaults.standard.object(forKey: "backgroundEnabled") == nil)
}
```

#### 5. SettingsView unit test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Both `SettingsView(...)` constructions gain
`backgroundEnabled: .constant(true)`; assertions gain
`#expect(bodyDescription.contains("Background"))`.

#### 6. UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

New flow test. Because `--seed` resets `backgroundEnabled` on every launch,
persistence-across-relaunch is verified via a second `--ui-testing` launch
(which does NOT reset `.standard`):

```swift
@MainActor
func testBackgroundToggleHidesAndPersistsAcrossRelaunch() {
    let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
    XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
    app.buttons["Settings"].tap()

    let toggle = app.switches["Background"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3))
    XCTAssertEqual(toggle.value as? String, "1", "Background should default to on")
    toggle.tap()
    XCTAssertEqual(toggle.value as? String, "0", "Tapping should hide the background")

    app.buttons["Done"].tap()
    app.terminate()

    let relaunched = XCUIApplication()
    relaunched.launchArguments = ["--ui-testing"]
    relaunched.launch()
    relaunched.buttons["Settings"].tap()
    let persistedToggle = relaunched.switches["Background"]
    XCTAssertTrue(persistedToggle.waitForExistence(timeout: 5))
    XCTAssertEqual(
        persistedToggle.value as? String, "0",
        "Background-off should persist across relaunch")
}
```

(Adjust the switch lookup if XCUITest exposes the Form Toggle differently,
e.g. `app.switches.firstMatch` scoped to the sheet — confirm during
implementation.)

### Verification

#### Automated
- [ ] `-only-testing:SingleThreadTests` passes including updated `SettingsViewTests` and new `UITestingSeedTests` case
- [ ] `-only-testing:SingleThreadUITests` passes including `testBackgroundToggleHidesAndPersistsAcrossRelaunch`
- [ ] Accessibility audit still green (new Toggle inherits standard hit region/dynamic type)

#### Manual
- [ ] Toggle off → photo disappears instantly, plain background returns; toggle on → photo restored with no network refetch (airplane-mode-safe)
- [ ] Disk files in `Application Support/SingleThread/` unchanged when toggled off
- [ ] Fresh install defaults to ON

---

## Phase 3: Attribution footer

### Changes

#### 1. SettingsView footer section
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

a) Both inits gain `backgroundPhotographer: String?` parameter; stored
property `private let backgroundPhotographer: String?`.

b) New footer Section on the main Form, placed after the Excluded Projects
Section (uses the `Section { } footer: { Text(…) }` precedent from
`ExcludedProjectsView`):

```swift
Section {
} footer: {
    if let backgroundPhotographer {
        Text("Photo by \(backgroundPhotographer) on Unsplash")
    }
}
```

c) Both `#Preview` blocks gain `backgroundPhotographer: "NEOM"` (one preview
can use `nil` to exercise the empty state).

#### 2. ContentView wiring
**File**: `SingleThread/ContentView.swift`
**Action**: modify

Both `SettingsView(...)` constructions in `.sheet` gain:

```swift
backgroundPhotographer: backgroundImage.photographer,
```

Because `photographer` is `@Observable` state read during body evaluation,
the footer updates live when a fetch completes mid-session. Credit always
matches the displayed photo: both are written by the same sidecar persist.

#### 3. Footer-state unit tests
**File**: `SingleThreadTests/BackgroundImageStoreTests.swift`
**Action**: modify

Append two cases pinning the store state the footer reads:
- `photographerMatchesStoredPhotoAfterFetch` — after a successful fetch,
  re-read the sidecar from disk and `#expect` its `photographer` equals
  `store.photographer` (pairing invariant).
- `photographerClearedWithoutValidSidecar` — delete (or corrupt) the sidecar,
  call `refreshIfNeeded` with the fake throwing → `store.photographer` is nil
  (footer renders empty).

#### 4. SettingsView unit test
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

Both constructions gain `backgroundPhotographer:` (use `"NEOM"` in one);
assertion gains `#expect(bodyDescription.contains("Unsplash"))`.

### Verification

#### Automated
- [ ] Full gate `./scripts/test.sh` green (format, lint, build, Periphery, unit tests, UI tests + accessibility audit on iPhone 17 and iPad (A16))
- [ ] New store pairing/cleared-metadata cases pass in `BackgroundImageStoreTests`

#### Manual
- [ ] After fetch succeeds: Settings footer reads "Photo by {photographer} on Unsplash" and matches the photographer of the visible photo
- [ ] Fresh install before first success: no footer text
- [ ] iPad (A16): photo crops sensibly (`scaledToFill` across aspect ratios), toggle + footer behave identically

---

## Testing Checkpoints (resume anchors)

- **Phase 1**: unit suite green with fake fetcher (success / rejection /
  retention / staleness / freshness / corrupt-sidecar); photo renders at 50%
  opacity full-bleed in light + dark; silent until first success; disk layout
  exists under Application Support.
- **Phase 2**: toggle hides/restores instantly without touching disk;
  `backgroundEnabled` cleared by `resetPersistedState()`; UI test covers flip +
  relaunch persistence via the `--ui-testing` second launch.
- **Phase 3**: footer mirrors stored metadata exactly, absent with no photo;
  full `./scripts/test.sh` green including Periphery and the accessibility
  audit on both sims.

Watch/widget remain untouched throughout — no App Group writes, no
`SkippedReminderSyncService` payload changes.

## Deviations from structure.md

1. **Protocol method named `fetchData(from:)`**, not `data(from:)` —
   URLSession's built-in `data(from:)` does not throw on non-2xx, so the
   conformance wraps it with HTTP-status validation under a distinct name.
   Same seam shape; makes the "reject non-2xx" requirement actually testable.
2. **Image layer extras** `.allowsHitTesting(false)` +
   `.accessibilityHidden(true)` and an `#if os(iOS)` guard — decorative
   full-bleed layer must not steal touches or enter the a11y tree, and the
   feature is iPhone/iPad-scoped while the app target also builds macOS.
3. **Relaunch persistence in the UI test uses a second `--ui-testing`
   launch** — a relaunch with `--seed` calls `resetPersistedState()` and would
   wipe the very key under test.
