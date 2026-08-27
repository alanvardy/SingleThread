# Implementation Plan

## Overview

Extend `BackgroundImageStore` with a 24-hour staleness default, a force-refresh path, and an observable `isRefreshing` flag; thread the live store through `SettingsView` → `BackgroundSettingsView` (replacing frozen credit snapshots) and add a "Refresh wallpaper" button with `ProgressView` feedback so the user can fetch a fresh Unsplash photo on demand.

---

## Phase 1: Store Layer — `BackgroundImageStore` extensions

### Changes

#### 1. Freshness constant + default `maxAge` + `isRefreshing` flag + `forceRefresh()`
**File**: `SingleThread/BackgroundImageStore.swift`
**Action**: modify

Add the constant in the `// MARK: Internal` section (right before `imageData`):

```swift
    /// A stored wallpaper is considered fresh for 24 hours before the network
    /// is consulted again.
    static let defaultMaxAge: TimeInterval = 86_400
```

Add the observable flag alongside the other `private(set)` state vars:

```swift
    /// `true` while an explicit force-refresh is in-flight; drives the button's
    /// `ProgressView` and disables it to prevent double-fetch.
    private(set) var isRefreshing = false
```

Give `refreshIfNeeded` a default parameter (only the signature line changes):

```swift
    func refreshIfNeeded(maxAge: TimeInterval = Self.defaultMaxAge) async {
```

Add `forceRefresh()` immediately after `refreshIfNeeded`. It skips the `isFresh` guard but reuses the same fetch → decode → validate → persist → flip-state pipeline, with the same "disk first, keep prior state on error" convention, toggling `isRefreshing` around the network work:

```swift
    /// Fetches a fresh wallpaper immediately, ignoring the staleness check.
    /// Unlike `refreshIfNeeded`, this always hits the network and toggles
    /// `isRefreshing` so the button can show progress. On any error it keeps
    /// the prior photo and attribution.
    func forceRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let payloadData = try await client.fetchData(from: Self.endpoint)
            let decoder = JSONDecoder()
            let payload = try decoder.decode(UnsplashPayload.self, from: payloadData)
            let data = try await client.fetchData(from: payload.url)
            guard isDecodableImage(data) else { throw URLError(.cannotDecodeContentData) }
            let metadata = BackgroundMetadata(
                photographer: payload.photographer,
                photographerURL: payload.photographerURL?.absoluteString,
                fetchedAt: Date())
            try persist(imageData: data, metadata: metadata) // disk before state
            imageData = data
            photographer = payload.photographer
            photographerURL = payload.photographerURL
        } catch {
            Self.logger.error("Background force refresh failed: \(error.localizedDescription)")
        }
    }
```

> Note: the pipeline body is duplicated from `refreshIfNeeded` rather than factored into a shared helper — per the design, no refactoring of existing code.

#### 2. Store unit tests
**File**: `SingleThreadTests/BackgroundImageStoreTests.swift`
**Action**: modify

Add six tests (four net-new, two adaptations of existing tests). Add a `FetchGate` actor and a `GatedBackgroundFetcher` helper to the `// MARK: Private` section to observe the in-flight `isRefreshing` flag.

```swift
    /// One-shot rendezvous that parks a fetch in-flight so a test can observe
    /// `isRefreshing` before releasing it.
    private actor FetchGate {
        private var parked: CheckedContinuation<Void, Never>?
        private var hitSignal: CheckedContinuation<Void, Never>?
        private var wasHit = false

        func wait() async {
            if wasHit { return }
            wasHit = true
            hitSignal?.resume()
            await withCheckedContinuation { parked = $0 }
        }

        func waitUntilHit() async {
            if wasHit { return }
            await withCheckedContinuation { hitSignal = $0 }
        }

        func open() {
            parked?.resume()
            parked = nil
        }
    }

    /// Parks the first (endpoint) fetch behind a gate, then serves valid data.
    private final class GatedBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
        let gate = FetchGate()
        private let endpointURL: URL
        var endpointData: Data = Data()
        var imageData: Data = Data()

        init(endpointURL: URL) {
            self.endpointURL = endpointURL
        }

        func fetchData(from url: URL) async throws -> Data {
            let isEndpoint = url == endpointURL
            if isEndpoint { await gate.wait() }
            return isEndpoint ? endpointData : imageData
        }
    }
```

New tests:

```swift
    @Test
    func forceRefreshBypassesFreshSidecar() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded() // seeds a fresh sidecar + photo
        let countAfterInitial = fake.requestedURLs.count
        #expect(countAfterInitial == 2)

        await store.forceRefresh()

        #expect(fake.requestedURLs.count > countAfterInitial,
                "forceRefresh should hit the network even with a fresh sidecar")
    }

    @Test
    func forceRefreshRetainsPriorImageOnFailure() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()

        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.forceRefresh()

        #expect(store.imageData == Self.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
        #expect(!store.isRefreshing, "failure path must reset isRefreshing")
    }

    @Test
    func forceRefreshUpdatesAttributionAfterSuccess() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()
        #expect(store.photographer == "NEOM")

        fake.stubbedData[Self.endpoint] = .success(Data(
            "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"Adele\"," +
            "\"photographer_url\":\"https://unsplash.com/@adele\"}".utf8))
        await store.forceRefresh()

        #expect(store.photographer == "Adele")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@adele")
        #expect(store.imageData == Self.jpegData)
    }

    @Test
    func isRefreshingToggledDuringForceRefresh() async throws {
        let fetcher = GatedBackgroundFetcher(endpointURL: Self.endpoint)
        fetcher.endpointData = payloadJSON()
        fetcher.imageData = Self.jpegData
        let store = BackgroundImageStore(
            client: fetcher,
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString))

        let task = Task { await store.forceRefresh() }
        await fetcher.gate.waitUntilHit()
        #expect(store.isRefreshing)
        await fetcher.gate.open()
        await task.value
        #expect(!store.isRefreshing)
    }
```

Adapt the two existing staleness tests to the default `maxAge` (rename + drop the `maxAge:` argument). Replace `staleSidecarTriggersRefetch` with:

```swift
    @Test
    func staleSidecarTriggersRefetchWith24hDefault() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()

        // 23h-old sidecar is still within the 24h default → skip.
        try sidecarJSON(fetchedAt: Date().addingTimeInterval(-23 * 3600))
            .write(to: store.metadataURL, options: .atomic)
        await store.refreshIfNeeded()
        let endpointCountWithinDay = fake.requestedURLs.filter { $0 == Self.endpoint }.count

        // 25h-old sidecar is beyond the 24h default → refetch.
        try sidecarJSON(fetchedAt: Date().addingTimeInterval(-25 * 3600))
            .write(to: store.metadataURL, options: .atomic)
        await store.refreshIfNeeded()
        let endpointCountBeyondDay = fake.requestedURLs.filter { $0 == Self.endpoint }.count

        #expect(endpointCountBeyondDay > endpointCountWithinDay,
                "only the 25h-old sidecar should trigger a refetch")
    }
```

Replace `freshSidecarSkipsNetwork` with:

```swift
    @Test
    func freshSidecarSkipsNetworkWith24hDefault() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded()
        #expect(fake.requestedURLs.count == 2)

        await store.refreshIfNeeded()

        #expect(fake.requestedURLs.count == 2, "Fresh sidecar should not trigger refetch")
    }
```

Add the sidecar-JSON helper next to `payloadJSON()`:

```swift
    /// Builds a minimal sidecar JSON with a `fetchedAt` relative to now.
    private func sidecarJSON(fetchedAt: Date) -> Data {
        let dateString = ISO8601DateFormatter().string(from: fetchedAt)
        return Data("{\"photographer\":\"Old\",\"fetchedAt\":\"\(dateString)\"}".utf8)
    }
```

### Verification
#### Automated
- [x] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests/BackgroundImageStoreTests` passes (14 tests: 8 existing + 4 net-new + 2 adapted)

#### Manual
- [ ] Cold-launch the app: the wallpaper still paints and its attribution still renders (now with a 24h staleness, so a second launch within a day hits no network).

---

## Phase 2: ContentViewModel — adopt default `maxAge`

### Changes

#### 1. Drop the hard-coded `3600` literal
**File**: `SingleThread/ContentViewModel.swift`
**Action**: modify

In `task(showUndatedReminders:)` (currently line 81):

```swift
        await backgroundImage.refreshIfNeeded(maxAge: 3600)
```
becomes
```swift
        await backgroundImage.refreshIfNeeded()
```

No other changes. `SingleThreadTests/BackgroundCardTests.swift:116` still passes `maxAge: 3600` explicitly — it compiles and passes unchanged (the default-parameter addition is source-compatible), so leave it as-is.

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadTests` passes

#### Manual
- [ ] No user-visible change; wallpaper fetch cadence is now governed by the store's 24h default.

---

## Phase 3: View threading — pass `BackgroundImageStore` to settings, add refresh button

### Changes

#### 1. `SettingsView` init + body + previews
**File**: `SingleThread/SettingsView.swift`
**Action**: modify

Replace the two read-only credit params with the store in `init`:

```swift
    init(
        bindings: SettingsBindings,
        backgroundImage: BackgroundImageStore,
        availableLists: [String],
        excludedLists: Binding<Set<String>>,
        viewModel: SettingsViewModel = SettingsViewModel()) {
        self.bindings = bindings
        self.viewModel = viewModel
        self.backgroundImage = backgroundImage
        self.availableLists = availableLists
        _excludedLists = excludedLists
    }
```

Drop the two stored properties `backgroundPhotographer` / `backgroundPhotographerURL` and add the store:

```swift
    private let viewModel: SettingsViewModel
    private let backgroundImage: BackgroundImageStore
    private let availableLists: [String]
```

Update the `NavigationLink` to `BackgroundSettingsView` in `body`:

```swift
                NavigationLink {
                    BackgroundSettingsView(
                        backgroundEnabled: $bindings.backgroundEnabled,
                        backgroundFadePercent: $bindings.backgroundFadePercent,
                        backgroundImage: backgroundImage)
                } label: {
                    Label("Background", systemImage: "photo.on.rectangle")
                }
```

Update both `#Preview`s — replace `backgroundPhotographer: "NEOM", backgroundPhotographerURL: URL(string: …)` (and the `nil`/`nil` pair in the second preview) with `backgroundImage: BackgroundImageStore()`.

#### 2. `BackgroundSettingsView` — store reference + refresh button
**File**: `SingleThread/BackgroundSettingsView.swift`
**Action**: modify

Replace the read-only credit constants with the observable store:

```swift
struct BackgroundSettingsView: View {
    @Binding var backgroundEnabled: Bool

    @Binding var backgroundFadePercent: Int

    var backgroundImage: BackgroundImageStore

    var body: some View {
        Form {
            Toggle(isOn: $backgroundEnabled) {
                Label("Background", systemImage: "photo")
            }
            Picker("Background Fade", selection: $backgroundFadePercent) {
                ForEach(BackgroundFade.allValues, id: \.self) { percent in
                    Text("\(percent)%").tag(percent)
                }
            }
            Section {
                Button {
                    Task { await backgroundImage.forceRefresh() }
                } label: {
                    HStack {
                        Label("Refresh wallpaper", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if backgroundImage.isRefreshing {
                            ProgressView()
                        }
                    }
                }
                .disabled(backgroundImage.isRefreshing)
            }
            Section {} footer: {
                if let photographer = backgroundImage.photographer {
                    if let url = backgroundImage.photographerURL {
                        Link(
                            "Photo by \(photographer) on Unsplash",
                            destination: url)
                    } else {
                        Text("Photo by \(photographer) on Unsplash")
                    }
                }
            }
        }
        .navigationTitle("Background")
    }
}
```

Update the `#Preview` — replace `backgroundPhotographer: "NEOM", backgroundPhotographerURL: URL(string: …)` with `backgroundImage: BackgroundImageStore()`.

#### 3. `ContentView` sheet call site
**File**: `SingleThread/ContentView.swift`
**Action**: modify

In the `.sheet` (currently lines 111–114):

```swift
                SettingsView(
                    bindings: bag,
                    backgroundImage: viewModel.backgroundImage,
                    availableLists: viewModel.store.availableLists,
                    excludedLists: excludedListsBinding,
                    viewModel: SettingsViewModel())
```

#### 4. Unit-test call sites for the changed inits
**File**: `SingleThreadTests/SettingsViewTests.swift`
**Action**: modify

This file was **not listed in `structure.md`**, but it must be updated or it will fail to compile after the init-signature change.

- `settingsViewContainsNavigationLinkLabels`: replace `backgroundPhotographer: nil, backgroundPhotographerURL: nil,` with `backgroundImage: BackgroundImageStore(),`.
- `backgroundSettingsViewContainsExpectedRows`: replace `backgroundPhotographer: "NEOM", backgroundPhotographerURL: Self.sampleURL)` with `backgroundImage: BackgroundImageStore())`.

### Verification
#### Automated
- [ ] `make build` succeeds (proves all previews + test inits compile)
- [ ] `./scripts/test.sh` passes (full CI gate: format, lint, build, periphery, unit + UI tests)

#### Manual
- [ ] Open Settings → Background: the new "Refresh wallpaper" row sits between the fade picker and the attribution footer.
- [ ] Tap it: a spinner appears while the button is disabled, then a fresh photo paints behind the list and the attribution footer updates to the new photographer/URL.
- [ ] Toggle/fade controls still behave as before.

---

## Phase 4: UI tests — refresh button reachability

### Changes

#### 1. New UI test
**File**: `SingleThreadUITests/SingleThreadUITestsFlows.swift`
**Action**: modify

Add to the Settings section (after `testBackgroundToggleHidesAndPersistsAcrossRelaunch`):

```swift
    // MARK: - Background refresh

    @MainActor
    func testBackgroundRefreshButtonExists() {
        let app = launchApp(seedJSON: #"{"reminders":[{"title":"Buy groceries"}]}"#)
        XCTAssertTrue(app.staticTexts["Buy groceries"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()

        // Navigate into the Background sub-view.
        XCTAssertTrue(app.staticTexts["Background"].waitForExistence(timeout: 3), "Settings should show Background")
        app.staticTexts["Background"].tap()

        let refreshButton = app.buttons["Refresh wallpaper"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 3), "Background settings should show the refresh button")
        XCTAssertTrue(refreshButton.isHittable)

        // Tap triggers forceRefresh(); the real URLSession may hit the network.
        // We assert only that the control is present and interactive, never the
        // fetched image (headless tests cannot assert rendering or network).
        refreshButton.tap()
        XCTAssertTrue(
            refreshButton.waitForExistence(timeout: 5),
            "Refresh button should remain in the tree after tap without crashing")
    }
```

The existing `testBackgroundToggleHidesAndPersistsAcrossRelaunch` is unchanged.

### Verification
#### Automated
- [ ] `xcodebuild test -scheme SingleThread -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SingleThreadUITests` passes (existing + 1 new)
- [ ] `./scripts/test.sh` passes (full CI gate)

#### Manual
- [ ] Run the app in the simulator, open Settings → Background, confirm the button is tappable and does not crash the app on tap.

---

## Final gate

- [ ] `make format` then `make lint` (SwiftFormat + SwiftLint `--strict`) clean
- [ ] `./scripts/test.sh` green end-to-end
