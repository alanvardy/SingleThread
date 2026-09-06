import UserNotifications

/// Test seam: wraps the UNUserNotificationCenter surface the app calls so tests
/// can inject a recording fake. Follows the EventKitStoring / SpeechTranscribing pattern.
@MainActor
public protocol UserNotificationCentering: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers: [String])
    func removeDeliveredNotifications(withIdentifiers: [String])
}

/// Real conformance
extension UNUserNotificationCenter: UserNotificationCentering {
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

/// Recording fake for unit tests.
/// @unchecked Sendable: mutable stored-property writes are
/// confined to @MainActor in the test target.
public final class FakeUserNotificationCenter: UserNotificationCentering, @unchecked Sendable {
    // MARK: Lifecycle

    // MARK: Init

    public init() {}

    // MARK: Public

    // MARK: Authorization

    public var authorizationRequested = false
    public var authorizationOptions: UNAuthorizationOptions?
    /// Injected result for requestAuthorization — default true.
    public var authorizationResult = true

    // MARK: Authorization status

    /// The status `authorizationStatus()` returns. Default `.notDetermined`.
    public var authorizationStatusOverride: UNAuthorizationStatus = .notDetermined

    // MARK: Scheduling

    public private(set) var addedRequests: [UNNotificationRequest] = []

    // MARK: Removal

    public private(set) var removedPendingIdentifiers: [String] = []
    public private(set) var removedDeliveredIdentifiers: [String] = []

    // MARK: UserNotificationCentering

    public func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequested = true
        authorizationOptions = options
        return authorizationResult
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusOverride
    }

    public func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }
}
