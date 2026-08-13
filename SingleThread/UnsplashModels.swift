//
//  UnsplashModels.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation

nonisolated struct BackgroundPhoto: Equatable {
    let imageURL: URL
    let photographerName: String
    let photographerProfileURL: URL
}

nonisolated struct UnsplashSearchResponse: Decodable {
    let total: Int
    let results: [UnsplashPhoto]
}

nonisolated struct UnsplashPhoto: Decodable {
    let urls: UnsplashURLs
    let user: UnsplashUser
}

nonisolated struct UnsplashURLs: Decodable {
    let regular: URL
}

nonisolated struct UnsplashUser: Decodable {
    let name: String
    let links: UnsplashUserLinks
}

nonisolated struct UnsplashUserLinks: Decodable {
    let html: URL
}
