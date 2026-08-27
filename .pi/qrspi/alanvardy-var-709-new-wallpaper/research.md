# Research Findings — Background Photograph: Fetch / Persist / Surface + Settings + Testing

Focus files: `SingleThread/BackgroundImageStore.swift`, `SingleThread/BackgroundSettingsView.swift`,
`SingleThread/SettingsView.swift`, `SingleThread/SettingsBindings.swift`,
`SingleThread/ContentViewModel.swift`, `SingleThread/AppViewModel.swift`.

---

## Q1: Fetch / persist / serve flow in `BackgroundImageStore.swift`

### Findings
- **Injected persistence + transport.** `BackgroundImageStore.init(client:directory:)` defaults to
  `URLSession.shared` and a computed `defaultDirectory` under Application Support, but tests inject a
  fake client and a UUID temp directory (`BackgroundImageStore.swift:61`). `directory` implemented
  as `FileManager` `.applicationSupportDirectory`/`SingleThread` (`:115-121`).
- **Observable served state** is three `private(set)` values: `imageData: Data?`, `photographer: String?`,
  `photographerURL: URL?` (`:69-73`). Two persisted file locations: `imageURL` = `background.jpg`,
  `metadataURL` = `background.json` (`:75-81`).
- **`refreshIfNeeded(maxAge:)` decision** (`:88-109`): first `loadStoredImage()` (`:89`) loads whatever is
  on disk into state, then `guard !isFresh(maxAge:) else { return }` (`:91`) short-circuits the network
  when stored data is still fresh. Only when missing/corrupt/stale does it hit the network.
- **Network path** (`:92-96`): two sequential `fetchData` calls — (1) `Self.endpoint` (metadata JSON), decode
  `UnsplashPayload`; (2) `payload.url` (the actual photo bytes). Then `guard isDecodableImage(data)`.
- **What gets persisted** (`:99-103`): a `BackgroundMetadata` sidecar (photographer, photographerURL as
  `String?`, `fetchedAt: Date()` ISO-8601 — `:32-37, :149-152, :167-168`) plus the raw photo bytes — one
  `persist(imageData:metadata:)` call that writes BOTH photo bytes and sidecar so the photo and its credit
  can never disagree (comment at `:82-84`). `persist` writes `background.jpg` (`.atomic`) and
  `background.json` (`.atomic`). Failure conventions: **disk first, then observable state** (`:103` `imageData = ...`); on any error just logs and keeps prior state (`:107-109`).
- **Staleness from sidecar** (`:142-150`): `isFresh` reads `metadata.json`, `decodeMetadata` (which uses
  `.iso8601` date strategy, `:149-152`), compares `Date().timeIntervalSince(metadata.fetchedAt) < maxAge`.
  Missing or corrupt sidecar ⇒ treats as **not fresh** (`:146-149`).
- **`loadStoredImage`** (`:126-137`): reads `metadataData`, `decodeMetadata`, `image`, `isDecodableImage`;
  if any step fails, clears `imageData`/`photographer`/`photographerURL` to nil and returns early; otherwise
  populates state from stored bytes+metadata. A missing sidecar with orphaned `background.jpg` means the photo
  is not surfaced (covered by a unit test).
- **Platform images** — `isDecodableImage` uses `UIImage(data:)` on iOS, `NSImage(data:)` on macOS
  (`:155-161`).
- **Unit-test observation:** `BackgroundImageStoreTests` asserts network "fetch" calls via `FakeBackgroundFetcher.requestedURLs` counter, e.g. `freshSidecarSkipsNetwork` asserts URL count stays 2 on a second
  `refreshIfNeeded`.

## Q2 — Network requests & validation

### Findings
- **`BackgroundImageFetching` protocol** (`BackgroundImageStore.swift:11-15`): a single async
  `func fetchData(from url: URL) async throws -> Data`. Documented as an abstraction so unit tests inject a
  fake.
- **`URLSession` conformance** (`:18-26`): wraps `URLSession`'s native `data(from:)` and adds explicit
  HTTP-status validation — because URLSession's own `data(from:)` does **not** throw on non-2xx (comment
  `:9-13`). `guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)` else
  throws `URLError(.badServerResponse)`.
- **Endpoint URL**: `private static let endpoint = URL(string: "https://vardy.cc/unsplash")!` (`:112`), the
  JSON metadata endpoint (GET).
- **Payload shape** — `UnsplashPayload: Decodable` (`:39-47`) decodes `url`, `photographer`,
  `photographerURL` (mapped from `photographer_url`); `created_at` is ignored.
- **Validation paths** in `refreshIfNeeded`:
  - Non-2xx → `URLError(.badServerResponse)` from the URLSession conformance; caught.
  - Undecodable JSON → `JSONDecoder.decode` throws; caught.
  - Non-image bytes: `guard isDecodableImage(data) else { throw URLError(.cannotDecodeContentData) }` (`:96`).
  - All failure paths hit the shared `catch { Self.logger.error(...) }` guard, which logs and keeps prior
    observable state (`:107-109`).
- **Logging** — `Logger(subsystem: "app.alanvardy.SingleThread", category: "BackgroundImage")` (`:113-114`).

## Q3 — Background state flow: creation → view layers + `maxAge`

### Findings
- **Creation**: `AppViewModel.init` owns a single `let backgroundImage = BackgroundImageStore()`
  (`AppViewModel.swift:76`, in `#if os(iOS)` composition block) — documented as a phone-local
  cosmetic that never touches the App Group or sync payload (class doc `:23-26`).
- **Composition root**: `AppViewModel` exposes a computed `contentViewModel` (`ContentViewModel(store:backgroundImage:speechTranscriber:ReminderDictation())`, `:96-101`), rebuilt on
demand so the view always reflects latest store/background state.
- **`ContentViewModel`** holds `let backgroundImage: BackgroundImageStore` (`ContentViewModel.swift:35`) and
  its `task(showUndatedReminders:)` drives refresh: `await backgroundImage.refreshIfNeeded(maxAge: 3600)`
  (`:78-82`).
- **`maxAge` configuration**: the staleness cap is **hard-coded to `3600` seconds (1 hour) as the only
  call site** at `ContentViewModel.swift:81`. No setting makes it user-configurable; `refreshIfNeeded` takes
  it as a parameter but only `.task` passes a real value.
- **`ContentView` → layer**:
  - `ContentView.init(viewModel:)` binds `backgroundImage` (already built in `AppViewModel`).
  - The `ZStack` layers, `Color.systemBackground` and `#if os(iOS) BackgroundPhotoLayer(...)`
    (`ContentView.swift:52-58`): `imageData: viewModel.backgroundImage.imageData`,
    `isEnabled: backgroundEnabled` (local `@AppStorage`), `opacity: BackgroundFade.opacity(for: backgroundFadePercent)`.
  - `.task { await viewModel.task(...) }` on `ContentView` (`:89`).
- **`BackgroundPhotoLayer`** struct (`BackgroundImageStore.swift:178-207`): iOS-only decorative layer; if
  `isEnabled && image != nil`, emits an overlay `Image` `.resizable().scaledToFill()` pinned by a
  `Color.clear` overlay, `.ignoresSafeArea()`, `.opacity(opacity)`, `.allowsHitTesting(false)`,
  `.accessibilityHidden(true)`. `opacity` is a SwiftUI opacity fraction.
- **`BackgroundFade`** enum (`SingleThread/BackgroundFade.swift`): default 50 (`:13`), step 10 (`:14`),
  `allValues` = `stride(from:0, through:90, by:10)` (`:16-18`), `opacity(for:)` = `1 - percent/100` clamped
  to 0…90 (`:20-22`). The layer opacity comes from this percentage.

Note: there is an additional `store.onRemindersChanged`/Widget relaunch path, but background refresh is
invoked **only** from `ContentView.task` — no timer or change-triggered refresh.

## Q4 — Settings assembly & how new rows/actions fit

### Findings
- **`SettingsView`** (`SingleThread/SettingsView.swift:11-111`): a modal presented via `NavigationStack`
  with a **`List` of `NavigationLink`s**, each label is a `Label(_:systemImage:)`. Rows: Interface (`:34-51`),
  Reminder (`:53-61`), Filtering & Sorting (`:63-70`), **Background (`:72-79`)**, Privacy Policy (`:81-84`).
  `.toolbar` with a confirmation "Done" (dismiss) (`:88-103`). `SettingsView` owns no state — everything is
  bound through a single `SettingsBindings` bag (`@Bindable`, `:106`).
- **`SettingsBindings`** (`:16-56`) is `@MainActor @Observable`, a one-bag holder of all preference
  `var`s, with defaults mirrored from `ContentView`'s `@AppStorage` (e.g. `backgroundEnabled` default
  `true`, `:55`; `backgroundFadePercent` default `50`, `:56`). Constructed on demand in
  `ContentView.makeSettingsBag()` (`ContentView.swift:489-511`) from the live `@AppStorage` properties, and
  written back to those properties via `.onChange(of: bag.…)` on the sheet (`ContentView.swift:121-135`,
  mirroring the `backgroundEnabled`/`backgroundFadePercent` pairs at `:128-129`).
- **` — BackgroundSettingsView`** (`SingleThread/BackgroundSettingsView.swift:7-38`) is a **`Form`** that
  takes **only the bindings it needs** (doc `:4-6`), not the whole bag: `backgroundEnabled: Binding<Bool>`,
  `backgroundFadePercent: Binding<Int>`, plus read-only constants `backgroundPhotographer`/`URL`. Controls:
  - `Toggle(isOn: $backgroundEnabled)` with `Label("Background", systemImage: "photo")` (`:18-19`).
  - `Picker("Background Fade", …)` over `ForEach(BackgroundFade.allValues)` (`:21-24`).
  - `Section {} footer: { … }` enclosing the attribution, `Link("Photo by … on Unsplash")`
    (`:26-34`).
  - `.navigationTitle("Background")` (`:38`).
  `NavigationLink` opens it with the bag-derived bindings + `viewModel.backgroundImage.photographer/URL`
  (`SettingsView.swift:73-78`).
- **Pattern to add a new row/action in the Settings area** (observed across existing sub-views):
- **Pattern to add a new row/action in the Settings area** (observed across existing sub-views):
  1. Add a `NavigationLink { … } label: { Label(...) }` row in `SettingsView`'s `List`, or add a control
     (`Toggle`/`Picker`/`Link`/`Button`) inside an existing sub-view `Form`/`List`.
  2. The value is mirrored across four places: a `@AppStorage`-backed property on `ContentView` (e.g.
     `backgroundFadePercent`, `ContentView.swift:161-162`); a `SettingsBindings` var built in
     `makeSettingsBag()` (`ContentView.swift:489-511`); a `@Binding` param on the sub-view; and a
     `.onChange(of: bag.<key>)` write-back onto the `@AppStorage` on the `.sheet` (`ContentView.swift:128-129`).

Note: `SettingsView`'s `init` takes a real `@Bindable` `SettingsBindings` plus the photographer values
separately so the credit can float as read-only background state (`:73-78`).

## Q5 — Testing seams for background behavior

### Findings
- **Fake network client** — `BackgroundImageStoreTests.swift:161-170`
  `private final FakeBackgroundFetcher: BackgroundImageFetching` records `requestedURLs` and serves a
  `stubbedData: [URL: Result<Data, Error>]` map; injected via `BackgroundImageStore(client:directory:)`.
- **Staging temp directories** — each test's `makeStore(...)` builds a fresh
  `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`
  (`BackgroundImageStoreTests.swift:200-207`); `orphanDirectory` variants add an orphan (no-sidecar) scenario (see `corruptOrMissingSidecarTreatedAsNoImage`). The `BackgroundCardTests` also uses this pattern.
- **Photo/metadata fixtures** — `jpegData` is a hand-built **1×1 smallest-valid JPEG** base64 blob in
  `BackgroundImageStoreTests.swift:174-186` (also duplicated in `BackgroundCardTests.swift:62-72`), used to
  pass the `isDecodableImage` gate. `payloadJSON()` (`:209-216`) builds the realistic `GET /unsplash` JSON
  (with optional `created_at` ignored). Sidecar fixtures are built inline (e.g. `staleMetadata` JSON strings
  rewritten over `metadataURL`, `:131-134`).
- **Unit tests for the store** (`BackgroundImageStoreTests.swift`, `@Suite(.serialized)`, `@MainActor`):
  - `successfulFetchStoresBytesAndMetadata`
  - `nonImagePayloadRejected` (asserts no files persisted + nil state)
  - `failedFetchRetainsPriorImage`
  - `staleSidecarTriggersRefetch`
  - `freshSidecarSkipsNetwork`
  - `corruptOrMissingSidecarTreatedAsNoImage`
  - `photographerURLMatchesStoredPhotoAfterFetch` (sidecar↔photo pairing invariant)
  - `photographerClearedWithoutValidSidecar`
  - (Plus `BackgroundFadeTests.swift`: default 50, steps→90, opacity inverse, clamp — `:8-`).
  - `BackgroundCardTests` asserts `rowChromeBackground == .clear` and plateFill colors without rendering
    (`.viewModel.rowChromeBackground` seam).
- **iOS UI tests — `--seed` / `InMemoryEventStore` seam**:
  - `UITestingSeed` (SingleThreadCore/Sources/SingleThreadCore/UITestingSeed.swift) parses
    `--seed '<json>'` (`fromLaunchArguments`), and `resetPersistedState()` clears both `.standard` **and**
    AppGroup keys — including **`backgroundEnabled`** (`persistedKeys` list) before launch.
  - `AppViewModel.makeStore(arguments:)` (`AppViewModel.swift:113-167`): when a `--seed` is present,
    builds an `InMemoryEventStore`, sets `usesInMemory`, and returns it (no EventKit). Sets `loadsReminders: true`.
  - `InMemoryEventStore` implements `EventKitStoring`, reports `.fullAccess`, filters completed reminders
    (`InMemoryEventStore.swift`).
  - UI driver helper: `launchApp(seedJSON:)` sets `app.launchArguments = ["--seed", seedJSON]`
    (`SingleThreadUITestsFlows.swift:46-72`).
- **Background UI test**: `testBackgroundToggleHidesAndPersistsAcrossRelaunch`
  (`SingleThreadUITestsFlows.swift:163-193`) — seeds a reminder, opens Settings→Background, flips the
  toggle, relaunches... **with `--ui-testing` for the relaunch, not `--seed`**, because a second `--seed`
  would call `resetPersistedState()` and wipe the very key under test. This is an explicit documented
  seam (comment `:179-186`). The persisted toggle is asserted via `--ui-testing` (which sets
  `enableActionButtons` in `.standard` but does **not** reset `.standard` defaults).
- **Other UI tests**: `--ui-testing` used in `ActionButtonsUITests`, `SingleThreadUITests`,
  `SingleThreadUITestsLaunchTests`.
- **Visual rendering headless limitation**: the wallpaper's actual painting is **not** asserted
  headlessly; tests assert the decision seams instead (e.g. `BackgroundCardTests` asserts
  `viewModel.rowChromeBackground == .clear`). Manual/review verification is expected for the blur/opacity and row chrome.

---

## Cross-Cutting Observations

- **MainActor-heavier default**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on iOS/watch targets, so
  `BackgroundImageStore`, `ContentViewModel`, `AppViewModel`, `SettingsBindings`, `ContentView` are all
  MainActor-isolated. Unit tests annotate `@MainActor` explicitly (e.g. `BackgroundImageStoreTests`).
- **Two-tier UserDefaults ownership** maps to "cosmetic vs sync": `backgroundEnabled` / `backgroundFade
  Percent` live on `.standard` (`ContentView.swift:158-162`) and are **not** synced to the watch; sync
  data (skip, date, list, name) lives in `AppGroup.defaults` (see prior QRSPI research `.pi/qrspi/var-650`).
- **MVVM refactor posture** (post `var-697`): `AppViewModel` is the composition root; `ContentViewModel`
  owns presentation logic + forwards store mutations; the view (`ContentView`) stays declarative and reads
  `viewModel.backgroundImage.*`.
- **A single `maxAge` constant (3600) drives header staleness**; no setting surfaces it.

## Open Areas

- **Exact behaviour of `BackgroundSettingsView` `Footer Section` layout vs how new `Section {}`
  placeholders compose** was read but not heavily verified across all builtins.
- **`backgroundFadePercent` is NOT in `UITestingSeed.persistedKeys`** (only `backgroundEnabled` is), so
  UI relaunch-persistence is only covered for the enable toggle, not the fade picker.
- **Timing/refresh**: there is no periodic refresh — only a single `.task`-driven call at view appear; the
  impact on long-running sessions is not covered by tests.