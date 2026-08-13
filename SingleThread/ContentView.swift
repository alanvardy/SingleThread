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
        NavigationViewWrapper {
            reminderList
        }
        .task {
            await reminderStore.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await reminderStore.load()
                }
            }
        }
    }

    // MARK: Private

    @Environment(ReminderStore.self) private var reminderStore
    @Environment(\.scenePhase) private var scenePhase

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
            if visibleReminders.isEmpty {
                ContentUnavailableView("No overdue or due-today reminders", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(visibleReminders, id: \.reminder.calendarItemIdentifier) { visible in
                        ReminderRow(visible: visible)
                    }
                }
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
                #endif
            }
        }
    }
}

private struct VisibleReminder {
    let reminder: EKReminder
    let status: DueStatus
    let dueDate: Date
}

private struct ReminderRow: View {
    let visible: VisibleReminder

    var body: some View {
        VStack(alignment: .leading) {
            Text(visible.reminder.title ?? "Untitled")
            Text(visible.dueDate, format: Date.FormatStyle(date: .numeric, time: .standard))
                .font(.caption)
        }
        .foregroundStyle(visible.status == .overdue ? Color.red : Color.primary)
    }
}

private struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                content()
            } detail: {
                Text("Select a reminder")
            }
        #else
            content()
        #endif
    }
}

#Preview {
    ContentView()
        .environment(ReminderStore())
}
