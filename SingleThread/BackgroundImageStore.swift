import Foundation
#if os(iOS)
    import SwiftUI
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

/// Sidecar metadata persisted next to the photo bytes. One write covers both
/// the displayed photo and the attribution credit, so they can never disagree.
private struct BackgroundMetadata: Codable {
    let photographer: String
    let photographerURL: String?
    let fetchedAt: Date
}

/// Shape of the `GET https://vardy.cc/unsplash` JSON payload (`created_at` ignored).
private struct UnsplashPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case url
        case photographer
        case photographerURL = "photographer_url"
    }

    let url: URL
    let photographer: String
    let photographerURL: URL?
}

/// Fetches, persists, and serves the background photograph.
/// Phone-local cosmetic concern: never touches the App Group or sync payloads.
@MainActor
@Observable
final class BackgroundImageStore {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - client: network transport; production default is `URLSession.shared`.
    ///   - directory: persistence location; tests inject a UUID temp directory.
    init(client: any BackgroundImageFetching = URLSession.shared, directory: URL? = nil) {
        self.client = client
        self.directory = directory ?? Self.defaultDirectory
    }

    // MARK: Internal

    /// A stored wallpaper is considered fresh for 24 hours before the network
    /// is consulted again.
    static let defaultMaxAge: TimeInterval = 86_400

    /// Bytes of the currently-displayed photo, or nil before first success.
    private(set) var imageData: Data?
    /// Photographer of the currently-displayed photo, or nil.
    private(set) var photographer: String?
    /// Unsplash attribution URL for the currently-displayed photo, or nil.
    private(set) var photographerURL: URL?
    /// `true` while an explicit force-refresh is in-flight; drives the button's
    /// `ProgressView` and disables it to prevent double-fetch.
    private(set) var isRefreshing = false

    var imageURL: URL {
        directory.appendingPathComponent("background.jpg")
    }

    var metadataURL: URL {
        directory.appendingPathComponent("background.json")
    }

    /// Loads stored bytes into observable state, then refetches over the
    /// network when the sidecar is missing/corrupt/stale. Called from
    /// ContentView's `.task`; rendering is never gated on the network result.
    /// Failure convention: persist to disk FIRST, then flip observable state;
    /// on any error, log and keep prior state.
    func refreshIfNeeded(maxAge: TimeInterval = BackgroundImageStore.defaultMaxAge) async {
        loadStoredImage()
        guard !isFresh(maxAge: maxAge) else { return }
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
            Self.logger.error("Background refresh failed: \(error.localizedDescription)")
        }
    }

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

    // MARK: Private

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread", category: "BackgroundImage")

    private static var defaultDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SingleThread", isDirectory: true)
    }

    private let client: any BackgroundImageFetching
    private let directory: URL

    /// Missing/corrupt sidecar ⇒ treated as "no valid stored image".
    private func loadStoredImage() {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decodeMetadata(from: metadataData),
              let data = try? Data(contentsOf: imageURL),
              isDecodableImage(data)
        else {
            imageData = nil
            photographer = nil
            photographerURL = nil
            return
        }
        imageData = data
        photographer = metadata.photographer
        photographerURL = metadata.photographerURL.flatMap(URL.init)
    }

    private func isFresh(maxAge: TimeInterval) -> Bool {
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decodeMetadata(from: metadataData)
        else { return false }
        return Date().timeIntervalSince(metadata.fetchedAt) < maxAge
    }

    private func decodeMetadata(from data: Data) throws -> BackgroundMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackgroundMetadata.self, from: data)
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

#if os(iOS)
    /// Decorative full-bleed background photo layer shown behind the reminder
    /// list. Non-interactive and hidden from accessibility so it never steals
    /// touches or pollutes the a11y tree.
    struct BackgroundPhotoLayer: View {
        let imageData: Data?
        /// Toggled from Settings; `false` hides the photo without touching disk.
        var isEnabled = true
        /// Fade level as a SwiftUI opacity fraction, chosen in Settings.
        var opacity = BackgroundFade.opacity(for: BackgroundFade.defaultValue)

        var body: some View {
            if isEnabled, let image = imageData.flatMap(UIImage.init(data:)) {
                // The overlay wrapper pins the layer to its parent's size so
                // `scaledToFill` can never expand the surrounding layout.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .ignoresSafeArea()
                    .opacity(opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
#endif
