//
//  SingleThreadTests.swift
//  SingleThreadTests
//
//  Created by Alan Vardy on 2026-08-12.
//

import Foundation
import Testing

struct SingleThreadTests {
    // MARK: Internal

    @Test func completedReminderIsExcluded() {
        let due = DateComponents(year: 2026, month: 8, day: 12)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: true,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func missingDueDateIsExcluded() {
        let status = dueStatus(
            dueDateComponents: nil,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func yesterdayEndOfDayIsOverdue() {
        let due = DateComponents(year: 2026, month: 8, day: 11, hour: 23, minute: 59)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .overdue)
    }

    @Test func todayStartOfDayIsDueToday() {
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .dueToday)
    }

    @Test func todayEndOfDayIsDueToday() {
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 23, minute: 59)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == .dueToday)
    }

    @Test func tomorrowStartOfDayIsExcluded() {
        let due = DateComponents(year: 2026, month: 8, day: 13, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: Self.now,
            calendar: Self.calendar)
        #expect(status == nil)
    }

    @Test func halfPastMidnightIsDueTodayNotOverdue() throws {
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = try #require(TimeZone(secondsFromGMT: -8 * 3600))
        let localNowComponents = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 30)
        let localNow = try #require(localCalendar.date(from: localNowComponents))
        let due = DateComponents(year: 2026, month: 8, day: 12, hour: 0, minute: 0)
        let status = dueStatus(
            dueDateComponents: due,
            isCompleted: false,
            now: localNow,
            calendar: localCalendar)
        #expect(status == .dueToday)
    }

    // MARK: Private

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))!
}
