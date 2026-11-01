# Implementation Plan

## Overview

Contain Sentry issue 7821993169 (`Fatal App Hang Fully Blocked`, culprit
`SingleThreadApp.$main`) by dropping, in `beforeSend`, AppHang events whose
blocked chain is the system-only BackBoardServices/backlight XPC stall, while
still reporting every hang whose blockage includes app code; and move
`BackgroundImageStore`'s synchronous disk I/O off the MainActor.

---

## Pre-phase validation (plan step) — RESOLVED

Two facts the design left inferred are now verified against sentry-cocoa 9.29.2
and the raw event JSON. **Both change the predicate**, so they are recorded here
rather than left as implementation-time surprises.

1. **`beforeSend` runs on the fatal-flush path** (design open risk, resolved).
   `SentryHangTrackingIntegration.captureStoredAppHangEvent` →
   `SentrySDKInternal.captureFatalAppHang` → `SentryHub.captureFatalAppHangEvent`
   → `captureFatalEvent` → `sendEvent(... isFatalEvent:YES)` → `prepareEvent`
   → `beforeSend`. `SentryEvent.serialize` / `SentryFrameCodable` preserve
   `exceptions`, `stacktrace`, and `in_app` across the store/read cycle. ✅
2. **Function names are NOT available at `beforeSend`** (design assumption,
   false). App-hang stacks are built by
   `SentryDefaultThreadInspector.getCurrentThreadsWithStackTrace()` →
   `SentryStacktraceBuilder` → `SentryCrashStackEntryMapper.mapAddress:`, which
   sets only `instructionAddress`, `imageAddress`, `package` (= the loaded
   binary path) and `inApp`. The only `Frame.function` writer in the SDK is
   `SentryFrameCodable` (JSON decode of an already-symbolicated payload); there
   is no local symbolication. The design's denylist
   (`BKSDisplayBrightnessGetCurrent`, `bootstrap_look_up`) is therefore
   **unmatchable client-side**. The signature must be matched on image paths.
3. **The exception stack is not app-frame-free** (design assumption, false).
   The raw event's client-side exception stack contains exactly one app frame
   (`…/SingleThread.app/SingleThread`, `in_app: true`); server symbolication
   later splits it into `main` + `SingleThreadApp.$main`. A "zero app frames"
   condition never fires. The correct condition is "no app frame in the
   *blocked* (deepest) region".

**Deviations from `structure.md` (forced by the above), all confined to Phase 1–2:**

- Denylist is image paths, not function names:
  `systemStallSignatureImages = ["BackBoardServices", "libxpc.dylib"]`.
- `isSystemStall` takes the ordered `[StackFrameSignature]` (image + `isApp`)
  instead of `(frameSignatures, hasAppFrames)`; the app-frame condition becomes
  positional ("no in-app frame at or deeper than the first stall frame").
- The Phase 2 case `keepsEventWhenAnyFrameIsInApp` is implemented as
  `keepsEventWhenAppFrameIsInBlockedChain` (an app frame shallower than the
  stall — the real captured entry frame — must NOT prevent the drop).

The fixture is the raw event's **client-side** frame list (`package` + `in_app`)
verbatim — sentry-cocoa's equivalent of `raw_stacktrace.frames` in the JSON.

---

## Phase 1: Walking skeleton — drop the captured BackBoardServices stall in `beforeSend`

**Outcome**: the captured event (system-only blocked chain, app frame only at
the bottom) is dropped end to end through the real captured signature → pure
predicate → `SentryScrubber.scrub(_:) == nil`; the same hang with an app frame in
the blocked chain is reported unchanged.

### Changes

#### 1. `SingleThread/SentryScrubber.swift`
**Action**: modify

Add the signature constants, the reduced frame value, the pure predicate, and
the thin `Event` adapter, then short-circuit `scrub(_:)`.

```swift
enum SentryScrubber {
    /// Tag keys that carry app/device metadata only — never reminder content.
    nonisolated static let allowedTags: Set<String> = ["environment", "release", "level"]

    /// Binary-image substrings of the synchronous BackBoardServices/backlight XPC
    /// stall UIKit performs on the main thread. Sentry issue 7821993169:
    /// `BKSDisplayBrightnessGetCurrent` (BackBoardServices) →
    /// `bootstrap_look_up` (libxpc).
    ///
    /// Function names are NOT available in `beforeSend` — sentry-cocoa sets only
    /// `package`/`inApp` at capture and symbolicates `function` server-side — so
    /// the signature is matched on image paths.
    nonisolated static let systemStallSignatureImages: [String] = [
        "BackBoardServices",
        "libxpc.dylib",
    ]

    /// One frame reduced to the fields `beforeSend` actually receives.
    struct StackFrameSignature: Equatable {
        /// `Frame.package` — the loaded binary's path.
        let image: String
        /// `Frame.inApp`, with the app-bundle path as a belt-and-braces fallback.
        let isApp: Bool
    }

    /// Pure drop decision. Fail-open: any under-specified input returns `false`,
    /// so the event is reported rather than silently lost.
    ///
    /// All three conditions must hold:
    ///  1. the mechanism is the public, stable `"AppHang"` marker,
    ///  2. the blocked chain contains every image in `systemStallSignatureImages`,
    ///  3. no in-app frame sits at or deeper than the first stall frame.
    nonisolated static func isSystemStall(
        mechanismType: String?,
        frames: [StackFrameSignature]
    ) -> Bool {
        guard mechanismType == "AppHang" else { return false }
        guard !frames.isEmpty else { return false }
        guard systemStallSignatureImages.allSatisfy({ signature in
            frames.contains { $0.image.contains(signature) }
        }) else { return false }
        guard let firstStall = frames.firstIndex(where: { frame in
            systemStallSignatureImages.contains { frame.image.contains($0) }
        }) else { return false }
        return !frames[firstStall...].contains(where: \.isApp)
    }

    /// Reduces a Sentry event to an app-hang signature, or `nil` for any shape it
    /// does not recognise (fail-open).
    nonisolated static func appHangStack(
        in event: Event
    ) -> (mechanismType: String, frames: [StackFrameSignature])? {
        guard
            let exception = event.exceptions?.first(where: {
                $0.mechanism?.type == "AppHang"
            }),
            let mechanismType = exception.mechanism?.type,
            let stacktrace = exception.stacktrace,
            !stacktrace.frames.isEmpty
        else { return nil }
        return (mechanismType, stacktrace.frames.map(StackFrameSignature.init))
    }

    /// Allow-list scrubber… When the event is the captured system-stall hang the
    /// whole event is dropped; every other event is PII-scrubbed as before.
    nonisolated static func scrub(_ event: Event) -> Event? {
        if let stack = appHangStack(in: event),
           isSystemStall(mechanismType: stack.mechanismType, frames: stack.frames) {
            return nil
        }
        event.user = nil
        event.extra = nil
        // …existing body unchanged…
        return event
    }
    // …existing breadcrumb scrubber and allowedTags…
}

extension SentryScrubber.StackFrameSignature {
    init(_ frame: Frame) {
        let image = frame.package ?? ""
        self.image = image
        self.isApp = (frame.inApp?.boolValue == true) || image.contains(".app/")
    }
}
```

No `SentryBootstrap.swift` change: `beforeSend` already routes through
`scrub` (`SentryBootstrap.swift:38`).

#### 2. `SingleThreadTests/SentryScrubberTests.swift`
**Action**: modify

Add the captured-fixture helper and the Phase 1 cases.

```swift
private static let appImage =
    "/private/var/containers/Bundle/Application/277152F6-B99C-4FA0-BADB-098D8D06EC13/SingleThread.app/SingleThread"
private static let swiftUI = "/System/Library/Frameworks/SwiftUI.framework/SwiftUI"
private static let uiKit = "/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore"
private static let graphicsServices =
    "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices"
private static let coreFoundation =
    "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
private static let libDispatch = "/usr/lib/system/libdispatch.dylib"
private static let backBoard =
    "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices"
private static let libXPC = "/usr/lib/system/libxpc.dylib"
private static let libObjCMsgSend = "/usr/lib/objc/libobjcMsgSend.dylib"

/// The raw event's client-side exception stack (`package` + `in_app`), verbatim.
private static let capturedFrames: [(image: String, inApp: Bool)] = [
    ("dyld", false),
    (appImage, true),
    (swiftUI, false), (swiftUI, false), (swiftUI, false),
    (uiKit, false), (graphicsServices, false),
    (coreFoundation, false), (coreFoundation, false), (coreFoundation, false),
    (libDispatch, false), (libDispatch, false), (libDispatch, false), (libDispatch, false),
    (coreFoundation, false), (coreFoundation, false),
    (uiKit, false), (uiKit, false), (uiKit, false),
    (backBoard, false), (backBoard, false),
    (libXPC, false), (libXPC, false), (libXPC, false), (libXPC, false), (libXPC, false),
    (libObjCMsgSend, false),
]

private func hangEvent(
    frames: [(image: String, inApp: Bool)],
    mechanismType: String = "AppHang"
) -> Event {
    let event = Event()
    let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
    exception.mechanism = Mechanism(type: mechanismType)
    exception.stacktrace = Stacktrace(frames: frames.map { frame in
        let sentryFrame = Frame()
        sentryFrame.package = frame.image
        sentryFrame.inApp = NSNumber(value: frame.inApp)
        return sentryFrame
    })
    event.exceptions = [exception]
    return event
}

@Test
func dropsCapturedBacklightSystemStall() {
    #expect(SentryScrubber.scrub(hangEvent(frames: Self.capturedFrames)) == nil)
}

@Test
func keepsHangWithAppFrameInBlockedChain() {
    var frames = Self.capturedFrames
    let leaf = frames.count - 1
    frames[leaf] = (Self.appImage, true) // app is the blocked (deepest) frame
    #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
}

@Test
func keepsNonHangBacklightEvent() {
    let event = hangEvent(frames: Self.capturedFrames, mechanismType: "Crash")
    event.extra = ["reminderTitle": "Buy milk"]
    let scrubbed = SentryScrubber.scrub(event)
    #expect(scrubbed != nil)                       // not dropped
    #expect(scrubbed?.extra == nil)                // PII scrubbing still runs
}
```

### Verification

#### Automated
- [x] `make build` succeeds.
- [x] `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes (suite-level form; a bare case name matches zero under Swift Testing).
- [x] `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` reports no zero-match (the script exits non-zero on a zero-match).

#### Manual
- [ ] Confirm `dropsCapturedBacklightSystemStall` succeeds, i.e. `scrub` returns `nil` for the real captured client-side frame list.
- [ ] Confirm `keepsHangWithAppFrameInBlockedChain` and `keepsNonHangBacklightEvent` both return non-`nil`.

---

## Phase 2: Fail-open guarantee — SDK churn or odd shapes never lose signal

**Outcome**: every deviation from the exact filtered shape still reports the
event, so a sentry-cocoa change or a missing/empty stack surfaces as noise, never
silent loss.

### Changes

#### 1. `SingleThread/SentryScrubber.swift`
**Action**: review only (the guards written in Phase 1 already implement this)

Confirm the explicit fail-open returns:
- `appHangStack` returns `nil` when the mechanism is absent/renamed, the
  stacktrace is missing, or the frame list is empty.
- `isSystemStall` returns `false` when the mechanism is not `"AppHang"`, the
  frame list is empty, or either signature image is absent.
- The positional app check does not misfire when `frame.package` is `nil`
  (`image == ""`, `isApp` falls back to `inApp`).

#### 2. `SingleThreadTests/SentryScrubberTests.swift`
**Action**: modify

```swift
@Test
func keepsEventWhenMechanismRenamed() {
    #expect(SentryScrubber.scrub(hangEvent(
        frames: Self.capturedFrames, mechanismType: "AppHangRenamed")) != nil)
}

@Test
func keepsEventWhenStacktraceMissing() {
    let event = Event()
    let exception = Exception(value: "App hanging.", type: "App Hang Fully Blocked")
    exception.mechanism = Mechanism(type: "AppHang")
    event.exceptions = [exception]
    #expect(SentryScrubber.scrub(event) != nil)
}

@Test
func keepsEventWhenFrameListEmpty() {
    #expect(SentryScrubber.scrub(hangEvent(frames: [])) != nil)
}

@Test
func keepsEventWhenDenylistPartiallyMatches() {
    // BackBoardServices present, libxpc absent ⇒ not the backlight XPC stall.
    let frames = Self.capturedFrames.filter { $0.image != Self.libXPC }
    #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
}

@Test
func keepsEventWhenAppFrameIsInBlockedChain() {
    var frames = Self.capturedFrames
    frames.insert((Self.appImage, true), at: frames.count) // app frame at the leaf
    #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
}

@Test
func keepsEventWhenFramePackageIsMissing() {
    let frames = Self.capturedFrames.map { (image: "", inApp: $0.inApp) }
    #expect(SentryScrubber.scrub(hangEvent(frames: frames)) != nil)
}
```

### Verification

#### Automated
- [x] `scripts/test-one.sh SingleThreadTests/SentryScrubberTests` passes with the five fail-open negatives added.

#### Manual
- [ ] Confirm every new assertion is `scrub(event) != nil` (the event survives).
- [ ] Confirm no force-unwrap was introduced (SwiftLint bans it outside tests).

---

## Phase 3: `BackgroundImageStore` disk I/O off the MainActor

**Outcome**: the wallpaper store's synchronous `Data(contentsOf:)` /
`FileManager` reads and writes no longer execute on the MainActor.

**Deviation from `structure.md`**: the disk helpers are `@concurrent`, not plain
`nonisolated`. `SWIFT_APPROACHABLE_CONCURRENCY = YES` (set project-wide) makes a
plain `nonisolated async` function run on the **caller's** actor, so
`nonisolated` alone would keep the I/O on the MainActor. `@concurrent` (Swift
6.2+, available in the toolchain here — verified compiling and executing off the
MainActor) is required.

### Changes

#### 1. `SingleThread/BackgroundImageStore.swift`
**Action**: modify

Add the off-main executor and move disk work into it; make
`loadStoredImage()`/`isFresh(maxAge:)`/`persist(imageData:metadata:)` async; keep
`refreshIfNeeded`/`forceRefresh` signatures unchanged.

```swift
    /// Runs synchronous disk work on the concurrent executor, off the MainActor.
    /// `@concurrent` is required because `SWIFT_APPROACHABLE_CONCURRENCY` leaves a
    /// plain `nonisolated async` function on the caller's actor (here MainActor).
    /// Internal so tests can prove the executor leaves the MainActor.
    @concurrent
    nonisolated static func offMain<T: Sendable>(
        _ work: @Sendable () throws -> T
    ) async rethrows -> T {
        try work()
    }

    /// A decoded, validated wallpaper (plain `Sendable` value, no observable state).
    private struct LoadedImage: Sendable {
        let data: Data
        let photographer: String
        let photographerURL: URL?
    }

    func loadStoredImage() async {
        let metadataURL = self.metadataURL
        let imageURL = self.imageURL
        let loaded = await Self.offMain { () -> LoadedImage? in
            guard
                let metadataData = try? Data(contentsOf: metadataURL),
                let metadata = try? Self.decodeMetadata(from: metadataData),
                let data = try? Data(contentsOf: imageURL),
                Self.isDecodableImage(data)
            else { return nil }
            return LoadedImage(
                data: data,
                photographer: metadata.photographer,
                photographerURL: metadata.photographerURL)
        }
        guard let loaded else {
            imageData = nil
            photographer = nil
            photographerURL = nil
            return
        }
        imageData = loaded.data
        photographer = loaded.photographer
        photographerURL = loaded.photographerURL.flatMap(URL.init)
    }

    private func isFresh(maxAge: TimeInterval) async -> Bool {
        let metadataURL = self.metadataURL
        let fetchedAt = await Self.offMain { () -> Date? in
            guard
                let data = try? Data(contentsOf: metadataURL),
                let metadata = try? Self.decodeMetadata(from: data)
            else { return nil }
            return metadata.fetchedAt
        }
        guard let fetchedAt else { return false }
        return Date().timeIntervalSince(fetchedAt) < maxAge
    }

    private func persist(imageData: Data, metadata: BackgroundMetadata) async throws {
        let directory = self.directory
        let imageURL = self.imageURL
        let metadataURL = self.metadataURL
        try await Self.offMain {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let metadataData = try encoder.encode(metadata)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try imageData.write(to: imageURL, options: .atomic)
            try metadataData.write(to: metadataURL, options: .atomic)
        }
    }

    private func decodeMetadata(from data: Data) throws -> BackgroundMetadata {
        try Self.decodeMetadata(from: data) // becomes: nonisolated static
    }

    /// Now `nonisolated static` so it can run inside `offMain`.
    private nonisolated static func decodeMetadata(from data: Data) throws -> BackgroundMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackgroundMetadata.self, from: data)
    }

    /// Now `nonisolated static` so it can run inside `offMain`.
    private nonisolated static func isDecodableImage(_ data: Data) -> Bool {
        #if os(iOS)
            UIImage(data: data) != nil
        #elseif os(macOS)
            NSImage(data: data) != nil
        #endif
    }
```

Update the call sites inside the store:

```swift
    func refreshIfNeeded(maxAge: TimeInterval = BackgroundImageStore.defaultMaxAge) async {
        await loadStoredImage()
        guard !isPinned || imageData == nil else { return }
        guard !(await isFresh(maxAge: maxAge)) else { return }
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        do {
            let wallpaper = try await fetchWallpaper(from: Self.endpoint)
            guard !isPinned || imageData == nil else { return }
            try await commit(wallpaper)
        } catch {
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

    func forceRefresh() async {
        // …unchanged guards…
        do {
            let wallpaper = try await fetchWallpaper(from: Self.randomEndpoint)
            try await commit(wallpaper) // was: try commit(wallpaper)
        } catch { … }
    }

    private func commit(_ wallpaper: FetchedWallpaper) async throws {
        let metadata = BackgroundMetadata(
            photographer: wallpaper.photographer,
            photographerURL: wallpaper.photographerURL?.absoluteString,
            fetchedAt: Date())
        try await persist(imageData: wallpaper.data, metadata: metadata) // disk before state
        imageData = wallpaper.data
        photographer = wallpaper.photographer
        photographerURL = wallpaper.photographerURL
    }
```

Delete the two replaced private declarations (the old synchronous `decodeMetadata`
and `isDecodableImage`) so there is exactly one implementation each. Remove the
now-unused instance `decodeMetadata` wrapper if SwiftFormat/Periphery flags it.
All disk-before-state ordering is preserved.

#### 2. `SingleThreadTests/BackgroundImageStoreTests.swift`
**Action**: modify

Await the now-async `loadStoredImage` at the five existing call sites (lines
267, 318, 367, 396, 423):

```swift
        await store.loadStoredImage()
```

Add the off-main regression guard and a stored-image parity case:

```swift
    /// Regression guard for the removed synchronous `Data(contentsOf:)` on the
    /// MainActor: the executor used for all disk work must leave the MainActor.
    @Test
    func diskWorkRunsOffMainActor() async {
        let ranOnMain = await BackgroundImageStore.offMain { pthread_main_np() != 0 }
        #expect(ranOnMain == false)
    }

    /// A stored image still loads and a fresh sidecar still short-circuits the
    /// network after the disk work moved off-main.
    @Test
    func storedImageStillLoadsAndBlocksStaleRefetch() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(BackgroundTestFixtures.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded(maxAge: 3600)
        #expect(store.imageData == BackgroundTestFixtures.jpegData)

        await store.loadStoredImage()
        #expect(store.photographer == "NEOM")

        let countAfterLoad = fake.requestedURLs.count
        await store.refreshIfNeeded()
        #expect(fake.requestedURLs.count == countAfterLoad,
                "fresh sidecar must skip the network after the off-main move")
    }
```

### Verification

#### Automated
- [x] `make build` succeeds.
- [x] `scripts/test-one.sh SingleThreadTests/BackgroundImageStoreTests` passes (all pre-existing cases plus the two new ones).
- [x] `scripts/test-one.sh SingleThreadTests/BackgroundImageStoreTests` exits 0 (no zero-match).

#### Manual
- [ ] `diskWorkRunsOffMainActor` asserts `false` (the work runs off the MainActor).
- [ ] No public surface changed: grep for `refreshIfNeeded(`/`forceRefresh(` call sites (`ContentViewModel:156`, `BackgroundSettingsView:57`) and confirm they still compile unchanged.

---

## Testing checkpoints

- After Phase 1: `SingleThreadTests/SentryScrubberTests` green — the captured client-side stack is dropped; a blocked-chain app frame is kept.
- After Phase 2: same suite green with the six fail-open negatives added.
- After Phase 3: `SingleThreadTests/BackgroundImageStoreTests` green (off-main guard + parity) and the pre-existing cases still green.
- Once all three phases commit: run `make format` then `make lint` inline, then the full CI gate **once** via the `run-gate` skill (never `nohup`). No UI test is added — a UI test cannot trigger a BackBoardServices stall, and the change is a pure predicate (design decision).

## Files touched

| File | Phase | Action |
|---|---|---|
| `SingleThread/SentryScrubber.swift` | 1, 2 | modify |
| `SingleThreadTests/SentryScrubberTests.swift` | 1, 2 | modify |
| `SingleThread/BackgroundImageStore.swift` | 3 | modify |
| `SingleThreadTests/BackgroundImageStoreTests.swift` | 3 | modify |

No new files. No pbxproj change (synchronized file groups). No schema migration.
No new test target, so no `Makefile`/`scripts/test.sh` filter entries are needed.

## Residual risks (accepted)

- **Image-based signature is coarser than function names.** `BackBoardServices`
  + `libxpc.dylib` on an AppHang whose blocked region has no app frame is the
  filtered class; a genuine app hang traversing those images *deeper than the
  app frame* would be dropped. Bounded by the positional app-frame condition.
- **SDK churn.** If sentry-cocoa stops setting `inApp`/`package` or renames the
  `"AppHang"` mechanism, the predicate returns `false` and events are reported
  (fail-open noise), never silently lost — the Phase 2 negatives pin this.
- **Other system stalls** (CloudKit, StoreKit, cfprefsd) are not filtered;
  adding signatures remains a deliberate, reviewed act.
