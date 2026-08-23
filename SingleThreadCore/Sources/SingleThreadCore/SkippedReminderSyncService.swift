import Foundation
import os

#if os(iOS) || os(watchOS)
    import WatchConnectivity

    /// Test seam: WCSession is not mockable, so we abstract the calls we need.
    public protocol SkipSyncSession: AnyObject {
        func activate()
        func updateApplicationContext(_ applicationContext: [String: Any]) throws
        func sendMessage(
            _ message: [String: Any],
            replyHandler: (([String: Any]) -> Void)?,
            errorHandler: ((any Error) -> Void)?)
    }

    extension WCSession: SkipSyncSession {}

    /// Pushes and receives the skip-set between phone and watch via WatchConnectivity,
    /// and relays "complete reminder" requests from the watch to the phone.
    /// Uses `updateApplicationContext` for skip sync — latest-wins, auto-delivers on
    /// (re)connect — and `sendMessage` for interactive completion requests.
    public final class SkippedReminderSyncService: NSObject, WCSessionDelegate {
        // MARK: Lifecycle

        public init(
            session: any SkipSyncSession,
            skipStore: SkippedReminderStore,
            excludeStore: ExcludedProjectStore = ExcludedProjectStore(),
            sortStore: SortOptionStore = SortOptionStore(),
            showUndatedStore: ShowUndatedRemindersPreference = ShowUndatedRemindersPreference(),
            showDateStore: ShowDatePreference = ShowDatePreference(),
            sendsShowDate: Bool = true) {
            self.session = session
            self.skipStore = skipStore
            self.excludeStore = excludeStore
            self.sortStore = sortStore
            self.showUndatedStore = showUndatedStore
            self.showDateStore = showDateStore
            self.sendsShowDate = sendsShowDate
            super.init()
        }

        // MARK: Public

        /// Hook invoked on the iPhone when the watch asks to complete a reminder.
        /// Passes the completed reminder's identifier.
        ///
        /// Safety: written once from the main actor *before* `activate()` is
        /// called and only read afterwards on WCSession's delegate queue, giving
        /// a happens-before edge between the two threads. It is
        /// `nonisolated(unsafe)` because the closure captures the `@MainActor`
        /// `ReminderStore` and is therefore not `Sendable`.
        ///
        /// Removal plan: inject the handler through `init` as an immutable
        /// `@Sendable (String) -> Void` (capturing the store `[weak]`), and then
        /// delete the `nonisolated(unsafe)` annotation.
        public nonisolated(unsafe) var onCompleteReminderReceived: ((String) -> Void)?

        /// Hook invoked on the iPhone when the watch asks to delete a reminder.
        /// Passes the deleted reminder's identifier. Same write-once-before-activate /
        /// `nonisolated(unsafe)` rationale as `onCompleteReminderReceived`.
        public nonisolated(unsafe) var onDeleteReminderReceived: ((String) -> Void)?

        /// Hook invoked on the watch when the iPhone's "show undated reminders"
        /// preference arrives in a combined application context. Passes the new value.
        /// Same write-once-before-activate / `nonisolated(unsafe)` rationale as
        /// `onCompleteReminderReceived`.
        public nonisolated(unsafe) var onShowUndatedRemindersReceived: ((Bool) -> Void)?

        /// Hook fired on the counterpart when the "show due date" preference arrives
        /// in an application context. Passes the received value. Same
        /// write-once-before-activate / `nonisolated(unsafe)` rationale as
        /// `onCompleteReminderReceived`.
        public nonisolated(unsafe) var onShowDateReceived: ((Bool) -> Void)?

        /// Hook fired on the counterpart when the skipped-reminder identifier array
        /// arrives in an application context. Passes the received IDs. Fired **after**
        /// the skip store is persisted, so a watch-side handler can simply reload.
        /// Same write-once-before-activate / `nonisolated(unsafe)` rationale as
        /// `onCompleteReminderReceived`.
        public nonisolated(unsafe) var onSkippedIdentifiersReceived: (([String]) -> Void)?

        /// Hook fired on the counterpart when a new sort option is received.
        /// Shares the same write-once-before-activate invariant as
        /// `onCompleteReminderReceived`.
        public nonisolated(unsafe) var onSortOptionReceived: ((SortOption) -> Void)?

        /// Hook invoked on the counterpart watch/phone when excluded-project titles
        /// arrive in an application context. Passes the received title array. Same
        /// write-once-before-activate / `nonisolated(unsafe)` rationale as
        /// `onShowUndatedRemindersReceived`.
        public nonisolated(unsafe) var onExcludedProjectTitlesReceived: (([String]) -> Void)?

        public func activate() {
            if let wcSession = session as? WCSession {
                wcSession.delegate = self
            }
            session.activate()
        }

        /// Pushes a complete snapshot of every synced setting as one latest-wins
        /// application context. Sending a single context shape removes the risk that
        /// interleaved partial shapes overwrite each other's omitted keys across an
        /// interrupted connection.
        public func pushAll() {
            do {
                var context: [String: Any] = [
                    PayloadKey.skippedReminderIdentifiers: skipStore.load(),
                    PayloadKey.excludedProjectTitles: excludeStore.load(),
                    PayloadKey.showUndatedReminders: showUndatedStore.load(),
                    PayloadKey.sortOption: sortStore.load().rawValue
                ]
                if sendsShowDate {
                    context[PayloadKey.showDate] = showDateStore.isEnabled
                }
                try session.updateApplicationContext(context)
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push sync context: \(description, privacy: .public)")
            }
        }

        /// Ask the iPhone to complete a reminder (watch-side action).
        public func requestCompleteReminder(_ identifier: String) {
            session.sendMessage(
                [PayloadKey.completeReminderIdentifier: identifier],
                replyHandler: nil) { error in
                    let description = error.localizedDescription
                    Self.logger.error("Failed to send completion request: \(description, privacy: .public)")
                }
        }

        /// Ask the iPhone to delete a reminder (watch-side action).
        public func requestDeleteReminder(_ identifier: String) {
            session.sendMessage(
                [PayloadKey.deleteReminderIdentifier: identifier],
                replyHandler: nil) { error in
                    let description = error.localizedDescription
                    Self.logger.error("Failed to send delete request: \(description, privacy: .public)")
                }
        }

        // MARK: WCSessionDelegate

        public func session(
            _: WCSession,
            didReceiveApplicationContext applicationContext: [String: Any]) {
            apply(context: applicationContext)
        }

        /// Single receive path: decode → persist → notify for each present key;
        /// absent keys are no-ops. Handlers are snapshotted before invocation because
        /// they are written once from the main actor before `activate()`.
        private func apply(context: [String: Any]) {
            // Latest-wins: `updateApplicationContext` transmits the sender's full
            // set, so the received values are authoritative. Replacing (rather
            // than unioning) local values makes a "clear" update ([]) propagate.
            // ReminderStore.reload() prunes stale skip IDs on the next fetch.
            // The keys are independent — the skip IDs + show-undated + sort +
            // show-date travel in one combined context, while excluded-project
            // titles use a separate one — so any key may be present without the
            // others.
            if let receivedIDs = context[PayloadKey.skippedReminderIdentifiers] as? [String] {
                skipStore.save(receivedIDs)
                let handler = onSkippedIdentifiersReceived
                handler?(receivedIDs)
            }
            if let receivedTitles = context[PayloadKey.excludedProjectTitles] as? [String] {
                excludeStore.save(receivedTitles)
                let handler = onExcludedProjectTitlesReceived
                handler?(receivedTitles)
            }
            if let received = context[PayloadKey.showUndatedReminders] as? Bool {
                showUndatedStore.save(received)
                let handler = onShowUndatedRemindersReceived
                handler?(received)
            }
            if let rawValue = context[PayloadKey.sortOption] as? String,
               let option = SortOption(rawValue: rawValue) {
                sortStore.save(option)
                let handler = onSortOptionReceived
                handler?(option)
            }
            if let showDate = context[PayloadKey.showDate] as? Bool {
                showDateStore.set(showDate)
                let handler = onShowDateReceived
                handler?(showDate)
            }
        }

        public func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            if let identifier = message[PayloadKey.completeReminderIdentifier] as? String {
                let handler = onCompleteReminderReceived
                handler?(identifier)
            }
            if let identifier = message[PayloadKey.deleteReminderIdentifier] as? String {
                let handler = onDeleteReminderReceived
                handler?(identifier)
            }
        }

        public func session(
            _: WCSession,
            activationDidCompleteWith _: WCSessionActivationState,
            error: (any Error)?) {
            if let error {
                Self.logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        #if os(iOS)
            public func sessionDidBecomeInactive(_: WCSession) {}
            public func sessionDidDeactivate(_ wcSession: WCSession) {
                wcSession.activate()
            }
        #endif

        // MARK: Private

        /// Keys used in the WatchConnectivity payloads, shared by the sender and
        /// receiver so the two sides of the wire protocol cannot drift.
        private enum PayloadKey {
            static let skippedReminderIdentifiers = "skippedReminderIdentifiers"
            static let excludedProjectTitles = "excludedProjectTitles"
            static let completeReminderIdentifier = "completeReminderIdentifier"
            static let deleteReminderIdentifier = "deleteReminderIdentifier"
            static let showUndatedReminders = "showUndatedReminders"
            static let sortOption = "sortOption"
            static let showDate = "showDate"
        }

        private static let logger = Logger(subsystem: "app.alanvardy.SingleThread", category: "ReminderSync")

        private let session: any SkipSyncSession
        private let skipStore: SkippedReminderStore
        private let excludeStore: ExcludedProjectStore
        private let sortStore: SortOptionStore
        private let showUndatedStore: ShowUndatedRemindersPreference
        private let showDateStore: ShowDatePreference
        private let sendsShowDate: Bool
    }
#endif
