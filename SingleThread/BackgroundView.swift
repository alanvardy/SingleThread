//
//  BackgroundView.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import SwiftUI

struct BackgroundView: View {
    // MARK: Internal

    var body: some View {
        if let photo = backgroundPhotoStore.photo {
            ZStack {
                AsyncImage(url: photo.imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .blur(radius: 24)
                .overlay(Color.black.opacity(0.35))

                VStack {
                    Spacer()
                    Link(
                        "Photo by \(photo.photographerName) on Unsplash",
                        destination: photo.photographerProfileURL)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: Private

    @Environment(BackgroundPhotoStore.self) private var backgroundPhotoStore
}
