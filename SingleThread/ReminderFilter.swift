//
//  ReminderFilter.swift
//  SingleThread
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation

nonisolated enum DueStatus {
    case overdue
    case dueToday
}

nonisolated func dueStatus(
    dueDateComponents: DateComponents?,
    isCompleted: Bool,
    now: Date,
    calendar: Calendar) -> DueStatus? {
    guard !isCompleted, let dueDateComponents, let dueDate = calendar.date(from: dueDateComponents) else {
        return nil
    }
    let startOfToday = calendar.startOfDay(for: now)
    if dueDate < startOfToday {
        return .overdue
    }
    if calendar.isDate(dueDate, inSameDayAs: startOfToday) {
        return .dueToday
    }
    return nil
}
