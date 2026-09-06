import Foundation
import UserNotifications

/// Schedules and cancels local idle-notification reminders.
/// Consumes `UserNotificationCentering` so tests inject a recording fake.
@MainActor
public final class NotificationScheduler {
    // MARK: Lifecycle

    public init(
        center: any UserNotificationCentering = UNUserNotificationCenter.current(),
        enabledKey: String = "notificationsEnabled",
        intervalHoursKey: String = "notificationIntervalHours",
        idleIdentifier: String = "app.alanvardy.SingleThread.idle-reminder",
        defaults: UserDefaults = UserDefaults.standard) {
        self.center = center
        self.enabledKey = enabledKey
        self.intervalHoursKey = intervalHoursKey
        self.idleIdentifier = idleIdentifier
        self.defaults = defaults
    }

    // MARK: Public

    /// The last successfully-scheduled request snapshot (for UI-test seam).
    public private(set) var lastScheduleSummary: String?

    /// The current pending-notification snapshot (for UI-test seam).
    public private(set) var pendingSummary: String?

    /// True only under `--ui-testing-notifications`; gates the status overlay.
    public var isUITestingNotifications: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-notifications")
    }

    /// Requests notification authorization (.alert + .badge) if status is
    /// `.notDetermined`. No-op otherwise (already granted or denied).
    /// When denied or the request throws, flips the enabled key to `false`
    /// so the UI toggle reflects reality.
    public func requestPermissionIfNeeded() async {
        let status = await center.authorizationStatus()
        switch status {
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await center.requestAuthorization(options: [.alert, .badge])
            } catch {
                defaults.set(false, forKey: enabledKey)
                return
            }
            if !granted {
                defaults.set(false, forKey: enabledKey)
            }
        default:
            break // already determined
        }
    }

    /// Cancels any pending idle reminder, then schedules a new one if
    /// notifications are enabled and `reminderCount > 0 || hasHidden`.
    /// The trigger fires after `intervalHours` (default 48h) with the
    /// reminder count in the body.
    public func scheduleIfNeeded(reminderCount: Int, hasHidden: Bool) async {
        await refreshPendingSummary()

        center.removePendingNotificationRequests(withIdentifiers: [idleIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [idleIdentifier])

        guard defaults.bool(forKey: enabledKey) else {
            lastScheduleSummary = nil
            return
        }
        guard reminderCount > 0 || hasHidden else {
            lastScheduleSummary = nil
            return
        }

        let intervalHours = defaults.integer(forKey: intervalHoursKey)
        let effectiveHours = intervalHours > 0 ? intervalHours : 48

        let content = UNMutableNotificationContent()
        content.title = String(localized: "SingleThread", table: "Localizable", bundle: .main)
        content.body = String(
            localized: "You have \(reminderCount) reminders waiting — open SingleThread!",
            table: "Localizable",
            bundle: .main)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Double(effectiveHours * 3600),
            repeats: false)

        let request = UNNotificationRequest(
            identifier: idleIdentifier,
            content: content,
            trigger: trigger)

        do {
            try await center.add(request)
            await refreshPendingSummary()
            lastScheduleSummary = Self.summary(requests: [request])
        } catch {
            lastScheduleSummary = nil
        }
    }

    /// Cancels all pending and delivered notifications.
    public func cancelAll() async {
        center.removePendingNotificationRequests(withIdentifiers: [idleIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [idleIdentifier])
        await refreshPendingSummary()
    }

    // MARK: Private

    private let center: any UserNotificationCentering
    private let enabledKey: String
    private let intervalHoursKey: String
    private let idleIdentifier: String
    private let defaults: UserDefaults

    /// Renders a pending-notification snapshot as a stable key=value
    /// status string for the UI-test seam.
    private static func summary(requests: [UNNotificationRequest]) -> String {
        guard let first = requests.first else { return "count=0" }
        let interval = (first.trigger as? UNTimeIntervalNotificationTrigger)
            .map { Int($0.timeInterval.rounded()) } ?? -1
        return "count=\(requests.count)\nid=\(first.identifier)\nbody=\(first.content.body)\ninterval=\(interval)"
    }

    private func refreshPendingSummary() async {
        guard isUITestingNotifications else { return }
        // Only the real center supports pendingNotificationRequests();
        // fake tests skip the summary path.
        guard let realCenter = center as? UNUserNotificationCenter else { return }
        let requests = await realCenter.pendingNotificationRequests()
        pendingSummary = Self.summary(requests: requests)
    }
}
