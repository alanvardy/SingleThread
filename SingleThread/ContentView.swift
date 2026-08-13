//
//  ContentView.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import EventKit
import SwiftUI

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        content
            .task {
                await reminderStore.load()
                await backgroundPhotoStore.load()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await reminderStore.load()
                    }
                }
            }
        #if os(iOS)
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
        #endif
    }

    // MARK: Private

    @Environment(ReminderStore.self) private var reminderStore
    @Environment(BackgroundPhotoStore.self) private var backgroundPhotoStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSaving = false
    @State private var completionError: String?
    @State private var isShowingSettings = false

    private var visibleReminders: [VisibleReminder] {
        let now = Date()
        let calendar = Calendar.current
        return reminderStore.reminders
            .compactMap { reminder -> VisibleReminder? in
                guard let status = dueStatus(
                    dueDateComponents: reminder.dueDateComponents,
                    isCompleted: reminder.isCompleted,
                    now: now,
                    calendar: calendar) else {
                    return nil
                }
                let dueDate = reminder.dueDateComponents.flatMap { calendar.date(from: $0) } ?? .distantFuture
                return VisibleReminder(reminder: reminder, status: status, dueDate: dueDate)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var currentReminder: VisibleReminder? {
        visibleReminders.first
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
            NavigationStack {
                ZStack {
                    BackgroundView()
                        .ignoresSafeArea()
                    reminderList
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        #else
            ZStack {
                BackgroundView()
                    .ignoresSafeArea()
                reminderList
            }
        #endif
    }

    @ViewBuilder
    private var reminderList: some View {
        switch reminderStore.accessStatus {
        case .notDetermined:
            ProgressView("Loading reminders…")
        case .denied:
            ContentUnavailableView(
                "Reminders access denied",
                systemImage: "bell.slash",
                description: Text("Enable Reminders access in Settings."))
        case .authorized:
            if let current = currentReminder {
                VStack {
                    Spacer()
                    ReminderCard(visible: current)
                    Spacer()
                    Button("Complete") {
                        complete(current)
                    }
                    .disabled(isSaving)
                    if let completionError {
                        Text(completionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")
            }
        }
    }

    private func complete(_ visible: VisibleReminder) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await reminderStore.complete(visible.reminder)
                completionError = nil
            } catch {
                completionError = "Couldn't complete the reminder. Please try again."
            }
        }
    }
}

private struct VisibleReminder {
    let reminder: EKReminder
    let status: DueStatus
    let dueDate: Date
}

private struct ReminderCard: View {
    let visible: VisibleReminder

    var body: some View {
        VStack(alignment: .leading) {
            Text(visible.reminder.title ?? "Untitled")
            Text(visible.dueDate, format: Date.FormatStyle(date: .numeric, time: .standard))
                .font(.caption)
        }
        .foregroundStyle(visible.status == .overdue ? Color.red : Color.primary)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
        .environment(ReminderStore())
}
