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

    init(searcher: any PhotoSearching = UnsplashPhotoSearch(), defaults: UserDefaults = .standard) {
        self.searcher = searcher
        self.defaults = defaults
    }

    // MARK: Internal

    static let accessKeyDefaultsKey = "unsplashAccessKey"

    private(set) var photo: BackgroundPhoto?

    func load() async {
        guard let accessKey = defaults.string(forKey: Self.accessKeyDefaultsKey),
              !accessKey.isEmpty else {
            Self.logger.info("BackgroundPhoto: no Unsplash access key set — skipping")
            photo = nil
            return
        }
        do {
            photo = try await searcher.search(accessKey: accessKey)
            let photographerName = photo?.photographerName ?? "?"
            Self.logger.info("BackgroundPhoto: loaded (photographer: \(photographerName))")
        } catch {
            Self.logger.error("BackgroundPhoto: load failed — \(error)")
            photo = nil
        }
    }

    // MARK: Private

    private static let logger = Logger(
        subsystem: "app.alanvardy.SingleThread",
        category: "BackgroundPhotoStore")

    private let defaults: UserDefaults
    private let searcher: any PhotoSearching
}
