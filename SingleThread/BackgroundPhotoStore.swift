//
//  BackgroundPhotoStore.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation
import Observation
import os

@MainActor
@Observable
final class BackgroundPhotoStore {
    // MARK: Lifecycle

    init(searcher: any PhotoSearching = UnsplashPhotoSearch()) {
        self.searcher = searcher
    }

    // MARK: Internal

    static let accessKeyDefaultsKey = "unsplashAccessKey"

    private(set) var photo: BackgroundPhoto?

    func load() async {
        guard let accessKey = UserDefaults.standard.string(forKey: Self.accessKeyDefaultsKey),
              !accessKey.isEmpty else {
            photo = nil
            return
        }
        do {
            photo = try await searcher.search(accessKey: accessKey)
        } catch {
            Self.logger.error("Background photo load failed: \(error)")
            photo = nil
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "BackgroundPhotoStore")

    private let searcher: any PhotoSearching
}
