//
//  BackgroundPhotoStoreTests.swift
//  SingleThreadTests
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation
@testable import SingleThread
import Testing

@Suite(.serialized)
@MainActor
struct BackgroundPhotoStoreTests {
    // MARK: Internal

    @Test func missingKeyClearsPhotoWithoutSearching() async {
        Self.defaults.removeObject(forKey: BackgroundPhotoStore.accessKeyDefaultsKey)
        let searcher = FakePhotoSearch(result: .failure(FakePhotoSearchError.boom))
        let store = BackgroundPhotoStore(searcher: searcher, defaults: Self.defaults)
        await store.load()
        #expect(store.photo == nil)
        #expect(searcher.searchCallCount == 0)
    }

    @Test func successLoadsPhotoFromSearcher() async throws {
        Self.defaults.set("test-key", forKey: BackgroundPhotoStore.accessKeyDefaultsKey)
        let expected = try BackgroundPhoto(
            imageURL: #require(URL(string: "https://images.unsplash.com/photo-1")),
            photographerName: "Jane Doe",
            photographerProfileURL: #require(URL(string: "https://unsplash.com/@janedoe")))
        let searcher = FakePhotoSearch(result: .success(expected))
        let store = BackgroundPhotoStore(searcher: searcher, defaults: Self.defaults)
        await store.load()
        #expect(store.photo == expected)
        #expect(searcher.searchCallCount == 1)
        #expect(searcher.lastAccessKey == "test-key")
    }

    @Test func failingSearchClearsPhoto() async {
        Self.defaults.set("test-key", forKey: BackgroundPhotoStore.accessKeyDefaultsKey)
        let searcher = FakePhotoSearch(result: .failure(FakePhotoSearchError.boom))
        let store = BackgroundPhotoStore(searcher: searcher, defaults: Self.defaults)
        await store.load()
        #expect(store.photo == nil)
    }

    // MARK: Private

    private static let defaults = UserDefaults(suiteName: "SingleThreadTests.BackgroundPhotoStore")!
}

@MainActor
private final class FakePhotoSearch: PhotoSearching {
    // MARK: Lifecycle

    init(result: Result<BackgroundPhoto, Error>) {
        self.result = result
    }

    // MARK: Internal

    var result: Result<BackgroundPhoto, Error>
    private(set) var searchCallCount = 0
    private(set) var lastAccessKey: String?

    func search(accessKey: String) async throws -> BackgroundPhoto {
        searchCallCount += 1
        lastAccessKey = accessKey
        return try result.get()
    }
}

private enum FakePhotoSearchError: Error {
    case boom
}
