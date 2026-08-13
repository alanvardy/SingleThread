//
//  SingleThreadApp.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import SwiftData
import SwiftUI

@main
struct SingleThreadApp: App {
    // MARK: Internal

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(reminderStore)
        .modelContainer(sharedModelContainer)
    }

    // MARK: Private

    @State private var reminderStore = ReminderStore()
}
