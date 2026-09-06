import SingleThreadCore
import Testing
import UserNotifications

@MainActor
struct UserNotificationCenteringTests {
    @Test
    func fakeRecordsAuthorizationRequest() async throws {
        let fake = FakeUserNotificationCenter()
        _ = try await fake.requestAuthorization(options: [.alert, .badge])
        #expect(fake.authorizationRequested)
        #expect(fake.authorizationOptions == [.alert, .badge])
    }

    @Test
    func fakeRecordsAuthorizationFailure() async throws {
        let fake = FakeUserNotificationCenter()
        fake.authorizationResult = false
        let result = try await fake.requestAuthorization(options: [])
        #expect(!result)
    }

    @Test
    func fakeRecordsAddedRequest() async throws {
        let fake = FakeUserNotificationCenter()
        let content = UNMutableNotificationContent()
        content.title = "Test"
        let request = UNNotificationRequest(identifier: "id", content: content, trigger: nil)
        try await fake.add(request)
        #expect(fake.addedRequests.count == 1)
        #expect(fake.addedRequests[0].identifier == "id")
    }

    @Test
    func fakeRecordsRemovedPending() {
        let fake = FakeUserNotificationCenter()
        fake.removePendingNotificationRequests(withIdentifiers: ["a", "b"])
        #expect(fake.removedPendingIdentifiers == ["a", "b"])
    }

    @Test
    func fakeRecordsRemovedDelivered() {
        let fake = FakeUserNotificationCenter()
        fake.removeDeliveredNotifications(withIdentifiers: ["x"])
        #expect(fake.removedDeliveredIdentifiers == ["x"])
    }

    @Test
    func fakeReturnsInjectedAuthorizationStatus() async {
        let fake = FakeUserNotificationCenter()
        fake.authorizationStatusOverride = .denied
        let status = await fake.authorizationStatus()
        #expect(status == .denied)
    }
}
