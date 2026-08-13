//
//  SettingsView.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import SwiftUI

struct SettingsView: View {
    // MARK: Internal

    var body: some View {
        #if os(iOS)
            NavigationStack {
                settingsForm
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                        }
                    }
            }
        #else
            settingsForm
                .frame(width: 380)
                .padding()
        #endif
    }

    // MARK: Private

    @AppStorage(BackgroundPhotoStore.accessKeyDefaultsKey) private var accessKey = ""
    @Environment(BackgroundPhotoStore.self) private var backgroundPhotoStore
    @Environment(\.dismiss) private var dismiss

    private var settingsForm: some View {
        Form {
            Section("Unsplash") {
                TextField("Access Key", text: $accessKey)
                Button("Save") {
                    Task {
                        await backgroundPhotoStore.load()
                    }
                }
            }
        }
    }
}
