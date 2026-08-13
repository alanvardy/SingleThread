//
//  SingleThreadApp.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import SwiftUI

@main
struct SingleThreadApp: App {
    // MARK: Internal

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .environment(reminderStore)
    }

    // MARK: Private

    @State private var reminderStore = ReminderStore()
}
