#if os(iOS) || os(watchOS)
    import SingleThreadCore
    import Testing
    import WatchConnectivity

    /// Push/receive tests for the watch→phone reschedule relay. Lives in its own
    /// file so `SkippedReminderSyncServiceTests.swift` stays under the
    /// `file_length` threshold.
    @MainActor
    struct RescheduleSyncTests {
        @Test
        func requestRescheduleReminderSendsMessage() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-send-\(suffix)"))
            var due = DateComponents()
            due.year = 2027
            due.month = 1
            due.day = 2
            due.hour = 10
            due.minute = 30

            service.requestRescheduleReminder(identifier: "ABC", dueDateComponents: due)

            let message = try #require(fake.lastMessage)
            let identifier = try #require(message["rescheduleReminderIdentifier"] as? String)
            let components = try #require(message["dueDateComponents"] as? [String: Int])
            #expect(identifier == "ABC")
            #expect(components == ["year": 2027, "month": 1, "day": 2, "hour": 10, "minute": 30])
        }

        @Test
        func requestRescheduleOmitsNilComponents() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-omit-\(suffix)"))
            var due = DateComponents()
            due.year = 2027
            due.month = 1
            due.day = 2

            service.requestRescheduleReminder(identifier: "ABC", dueDateComponents: due)

            let message = try #require(fake.lastMessage)
            let components = try #require(message["dueDateComponents"] as? [String: Int])
            #expect(components == ["year": 2027, "month": 1, "day": 2]) // hour/minute absent
        }

        @Test
        func receiveRescheduleReminderFiresHook() throws {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-recv-\(suffix)"))
            var receivedIdentifier: String?
            var receivedComponents: DateComponents?
            service.onRescheduleReminderReceived = { identifier, components in
                receivedIdentifier = identifier
                receivedComponents = components
            }

            service.session(
                WCSession.default,
                didReceiveMessage: [
                    "rescheduleReminderIdentifier": "XYZ",
                    "dueDateComponents": [
                        "year": 2027,
                        "month": 1,
                        "day": 2,
                        "hour": 10,
                        "minute": 30
                    ]
                ])

            #expect(receivedIdentifier == "XYZ")
            let components = try #require(receivedComponents)
            #expect(components.year == 2027)
            #expect(components.month == 1)
            #expect(components.day == 2)
            #expect(components.hour == 10)
            #expect(components.minute == 30)
        }

        @Test
        func receiveMessageWithoutRescheduleKeyIsNoOp() {
            let fake = FakeSession()
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-noop-\(suffix)"))
            var fired = false
            service.onRescheduleReminderReceived = { _, _ in fired = true }

            service.session(WCSession.default, didReceiveMessage: ["wrongKey": 42])

            #expect(!fired)
        }

        @Test
        func rescheduleRelaysWhenPhoneUnreachable() {
            let fake = FakeSession()
            fake.isReachable = false
            let suffix = UUID().uuidString
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-unreachable-\(suffix)"))

            service.requestRescheduleReminder(
                identifier: "ABC",
                dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

            #expect(fake.queuedUserInfo.count == 1)
            #expect(fake.lastMessage == nil)
        }

        @Test
        func rescheduleQueuesExactlyOnceWhenUnreachable() {
            let fake = FakeSession()
            fake.isReachable = false
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-xor-\(UUID().uuidString)"))

            service.requestRescheduleReminder(
                identifier: "ABC",
                dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

            #expect(fake.queuedUserInfo.count == 1)
            #expect(fake.lastMessage == nil) // send XOR queue, never both
            let queued = fake.queuedUserInfo[0]
            #expect(queued["rescheduleReminderIdentifier"] as? String == "ABC")
            #expect(queued["dueDateComponents"] as? [String: Int] == ["year": 2027, "month": 1, "day": 2])
        }

        @Test
        func rescheduleStillSendsWhenPhoneReachable() {
            let fake = FakeSession() // isReachable defaults true
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-send-\(UUID().uuidString)"))

            service.requestRescheduleReminder(
                identifier: "ABC",
                dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

            #expect(fake.lastMessage != nil)
            #expect(fake.queuedUserInfo.isEmpty)
        }

        @Test
        func rescheduleDoesNotQueueAfterSendError() {
            let fake = FakeSession()
            fake.errorToThrow = NSError(domain: "test", code: 1)
            let service = SkippedReminderSyncService(
                session: fake,
                skipStore: SkippedReminderStore(defaults: .standard, key: "test-resched-err-\(UUID().uuidString)"))

            service.requestRescheduleReminder(
                identifier: "ABC",
                dueDateComponents: DateComponents(year: 2027, month: 1, day: 2))

            #expect(fake.lastMessage != nil)
            #expect(fake.queuedUserInfo.isEmpty) // a rejected send is not retried on the queue
        }
    }
#endif
