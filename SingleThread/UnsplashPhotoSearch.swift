//
//  UnsplashPhotoSearch.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation

protocol PhotoSearching {
    func search(accessKey: String) async throws -> BackgroundPhoto
}

struct UnsplashPhotoSearch: PhotoSearching {
    func search(accessKey: String) async throws -> BackgroundPhoto {
        let url = URL(string: "https://api.unsplash.com/search/photos?query=nature&orientation=portrait")!
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
        guard let photo = randomPhoto(from: response.results) else {
            throw UnsplashSearchError.emptyResults
        }
        return BackgroundPhoto(
            imageURL: photo.urls.regular,
            photographerName: photo.user.name,
            photographerProfileURL: photo.user.links.html)
    }
}

nonisolated func randomPhoto(from results: [UnsplashPhoto]) -> UnsplashPhoto? {
    results.randomElement()
}

enum UnsplashSearchError: Error {
    case emptyResults
}
