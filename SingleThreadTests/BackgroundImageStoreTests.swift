import Foundation
@testable import SingleThread
import Testing

// MARK: - BackgroundImageStore Tests

@MainActor
@Suite(.serialized)
struct BackgroundImageStoreTests {
    // MARK: Internal

    @Test
    func successfulFetchStoresBytesAndMetadata() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == Self.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
        let savedImage = try Data(contentsOf: store.imageURL)
        #expect(savedImage == Self.jpegData)
        let savedMetadata = try Data(contentsOf: store.metadataURL)
        #expect(!savedMetadata.isEmpty)
        #expect(String(bytes: savedMetadata, encoding: .utf8)?.contains("NEOM") == true)
    }

    @Test
    func nonImagePayloadRejected() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Data("not an image".utf8))
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == nil)
        #expect(store.photographer == nil)
        #expect(!FileManager.default.fileExists(atPath: store.imageURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.metadataURL.path))
    }

    @Test
    func failedFetchRetainsPriorImage() async {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded(maxAge: 3600)

        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.imageData == Self.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")
    }

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

    @Test
    func corruptOrMissingSidecarTreatedAsNoImage() async throws {
        // Write background.jpg only — no sidecar.
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, directory) = makeStore(client: fake)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.jpegData.write(to: store.imageURL)

        await store.refreshIfNeeded(maxAge: 3600)

        // Sidecar missing ⇒ stored image is discarded and a network fetch runs;
        // here the fetch succeeds so state reflects the fresh payload.
        #expect(store.imageData == Self.jpegData)
        #expect(store.photographer == "NEOM")
        #expect(store.photographerURL?.absoluteString == "https://unsplash.com/@neom")

        // And with the fetch failing, no image surfaces from an orphaned jpg.
        struct StubError: Error {}
        let failingFake = FakeBackgroundFetcher()
        failingFake.stubbedData[Self.endpoint] = .failure(StubError())
        let orphanDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let orphanStore = BackgroundImageStore(client: failingFake, directory: orphanDirectory)
        try FileManager.default.createDirectory(
            at: orphanDirectory, withIntermediateDirectories: true)
        try Self.jpegData.write(to: orphanStore.imageURL)
        await orphanStore.refreshIfNeeded(maxAge: 3600)
        #expect(orphanStore.imageData == nil)
        #expect(orphanStore.photographer == nil)
    }

    /// Pairing invariant: the photographer and URL surfaced to the attribution footer
    /// always come from the same sidecar write as the displayed photo bytes.
    @Test
    func photographerURLMatchesStoredPhotoAfterFetch() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)

        await store.refreshIfNeeded(maxAge: 3600)

        let metadataData = try Data(contentsOf: store.metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct SidecarMetadata: Codable {
            let photographer: String
            let photographerURL: String?
            let fetchedAt: Date
        }
        let sidecar = try decoder.decode(SidecarMetadata.self, from: metadataData)
        #expect(sidecar.photographer == store.photographer)
        #expect(sidecar.photographerURL == store.photographerURL?.absoluteString)
    }

    @Test
    func photographerClearedWithoutValidSidecar() async throws {
        let fake = FakeBackgroundFetcher()
        fake.stubbedData[Self.endpoint] = .success(payloadJSON())
        fake.stubbedData[Self.imageURL] = .success(Self.jpegData)
        let (store, _) = makeStore(client: fake)
        await store.refreshIfNeeded(maxAge: 3600)
        #expect(store.photographer != nil)

        // Corrupt the sidecar, then fail the next fetch: state must fall back
        // to "no photo" so the footer renders empty rather than a stale credit.
        try Data("corrupt".utf8).write(to: store.metadataURL, options: .atomic)
        struct StubError: Error {}
        fake.stubbedData[Self.imageURL] = .failure(StubError())
        await store.refreshIfNeeded(maxAge: 3600)

        #expect(store.photographer == nil)
    }

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
            ("{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"Adele\"," +
                "\"photographer_url\":\"https://unsplash.com/@adele\"}").utf8))
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

    // MARK: Private

    private final class FakeBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
        private(set) var requestedURLs: [URL] = []
        var stubbedData: [URL: Result<Data, Error>] = [:]

        func fetchData(from url: URL) async throws -> Data {
            requestedURLs.append(url)
            return try stubbedData[url]!.get()
        }
    }

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

    /// Smallest valid JPEG (1×1 pixel), used to pass the decodability gate.
    private static let jpegData = Data(
        base64Encoded: "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEA"
            + "AKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAA"
            + "ABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkK"
            + "C//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYn"
            + "KCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqy"
            + "s7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAAB"
            + "AgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoW"
            + "JDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZ"
            + "mqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwIC"
            + "AwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQE"
            + "BxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQAC"
            + "EQMRAD8A+L6KKK/lM/38P//Z")!

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!

    private func makeStore(
        client: FakeBackgroundFetcher) -> (BackgroundImageStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (BackgroundImageStore(client: client, directory: directory), directory)
    }

    /// Builds a realistic `GET /unsplash` JSON payload pointing at the image URL
    /// and including the photographer_url attribution link.
    private func payloadJSON() -> Data {
        let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\"," +
            "\"photographer_url\":\"https://unsplash.com/@neom\",\"created_at\":\"2026-01-01\"}"
        return Data(json.utf8)
    }

    /// Builds a minimal sidecar JSON with a `fetchedAt` relative to now.
    private func sidecarJSON(fetchedAt: Date) -> Data {
        let dateString = ISO8601DateFormatter().string(from: fetchedAt)
        return Data("{\"photographer\":\"Old\",\"fetchedAt\":\"\(dateString)\"}".utf8)
    }
}
