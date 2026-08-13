//
//  UnsplashTests.swift
//  SingleThreadTests
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation
@testable import SingleThread
import Testing

struct UnsplashTests {
    // MARK: Internal

    @Test func decodesSearchResponseFixture() throws {
        let data = Data(Self.fixture.utf8)
        let response = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)
        #expect(response.total == 1)
        #expect(response.results.count == 1)
        let photo = response.results[0]
        #expect(photo.urls.regular == URL(string: "https://images.unsplash.com/photo-1?w=1080")!)
        #expect(photo.user.name == "Jane Doe")
        #expect(photo.user.links.html == URL(string: "https://unsplash.com/@janedoe")!)
    }

    @Test func randomPhotoReturnsNilForEmptyInput() {
        #expect(randomPhoto(from: []) == nil)
    }

    @Test func randomPhotoReturnsMemberOfInput() throws {
        let response = try JSONDecoder().decode(UnsplashSearchResponse.self, from: Data(Self.fixture.utf8))
        let photo = response.results[0]
        let result = randomPhoto(from: [photo])
        #expect(result?.urls.regular == photo.urls.regular)
        #expect(result?.user.name == photo.user.name)
    }

    // MARK: Private

    private static let fixture = """
    {
      "total": 1,
      "results": [
        {
          "urls": { "regular": "https://images.unsplash.com/photo-1?w=1080" },
          "user": {
            "name": "Jane Doe",
            "links": { "html": "https://unsplash.com/@janedoe" }
          }
        }
      ]
    }
    """
}
