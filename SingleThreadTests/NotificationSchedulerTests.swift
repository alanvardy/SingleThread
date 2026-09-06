import Foundation
@testable import SingleThreadCore
import Testing
import UserNotifications

@MainActor
struct NotificationSchedulerTests {
    // MARK: Internal

    @Test
    func schedulesWhenEnabled() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 2, hasHidden: false)
        #expect(fake.addedRequests.count == 1)
        let request = fake.addedRequests.first
        #expect(request?.identifier == "app.alanvardy.SingleThread.idle-reminder")
        #expect(request?.content.body.contains("2 reminders") == true)
        let trigger = request?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 172_800) // 48h default
    }

    @Test
    func skipsScheduleWhenDisabled() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake, enabled: false)
        await scheduler.scheduleIfNeeded(reminderCount: 5, hasHidden: false)
        #expect(fake.addedRequests.isEmpty)
    }

    @Test
    func skipsScheduleWhenNoReminders() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 0, hasHidden: false)
        #expect(fake.addedRequests.isEmpty)
    }

    @Test
    func schedulesWhenHasHidden() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 0, hasHidden: true)
        #expect(fake.addedRequests.count == 1)
    }

    @Test
    func requestsPermissionWhenNotDetermined() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .notDetermined
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.requestPermissionIfNeeded()
        #expect(fake.authorizationRequested)
        #expect(fake.authorizationOptions == [.alert, .badge])
    }

    @Test
    func skipsPermissionWhenAlreadyAuthorized() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .authorized
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.requestPermissionIfNeeded()
        #expect(!fake.authorizationRequested)
    }

    @Test
    func cancelRemovesPendingAndDelivered() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.cancelAll()
        #expect(fake.removedPendingIdentifiers.contains("app.alanvardy.SingleThread.idle-reminder"))
        #expect(fake.removedDeliveredIdentifiers.contains("app.alanvardy.SingleThread.idle-reminder"))
    }

    @Test
    func scheduleReplacesExistingPending() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake)
        await scheduler.scheduleIfNeeded(reminderCount: 1, hasHidden: false)
        await scheduler.scheduleIfNeeded(reminderCount: 2, hasHidden: false)
        // Second schedule removes the first request's id.
        #expect(fake.removedPendingIdentifiers.count >= 2) // once each schedule
        #expect(fake.addedRequests.count == 2) // both schedules added
    }

    @Test
    func usesConfiguredInterval() async {
        let fake = FakeUserNotificationCenter()
        let scheduler = Self.makeScheduler(center: fake, intervalHours: 24)
        await scheduler.scheduleIfNeeded(reminderCount: 1, hasHidden: false)
        let trigger = fake.addedRequests.first?.trigger as? UNTimeIntervalNotificationTrigger
        #expect(trigger?.timeInterval == 86400) // 24h
    }

    // MARK: Private

    /// Builds a scheduler against a recording fake + ephemeral UserDefaults.
    private static func makeScheduler(
        center: FakeUserNotificationCenter = FakeUserNotificationCenter(),
        enabled: Bool = true,
        intervalHours: Int = 48) -> NotificationScheduler {
        let defaults = UserDefaults(suiteName: "NotificationSchedulerTests-\(UUID().uuidString)")!
        defaults.set(enabled, forKey: "notificationsEnabled")
        defaults.set(intervalHours, forKey: "notificationIntervalHours")
        return NotificationScheduler(
            center: center,
            defaults: defaults)
    }
}
