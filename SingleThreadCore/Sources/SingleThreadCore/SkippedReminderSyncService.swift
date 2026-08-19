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
            excludeStore: ExcludedProjectStore = ExcludedProjectStore()) {
            self.session = session
            self.skipStore = skipStore
            self.excludeStore = excludeStore
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

        public func activate() {
            if let wcSession = session as? WCSession {
                wcSession.delegate = self
            }
            session.activate()
        }

        /// Push the full skip array to the counterpart.
        public func pushSkipIDs(_ ids: [String]) {
            do {
                try session.updateApplicationContext([PayloadKey.skippedReminderIdentifiers: ids])
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push skip IDs: \(description, privacy: .public)")
            }
        }

        /// Push the full excluded-project title array to the counterpart.
        public func pushExcludedProjectTitles(_ titles: [String]) {
            do {
                try session.updateApplicationContext([PayloadKey.excludedProjectTitles: titles])
            } catch {
                let description = error.localizedDescription
                Self.logger.error("Failed to push excluded project titles: \(description, privacy: .public)")
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

        // MARK: WCSessionDelegate

        public func session(
            _: WCSession,
            didReceiveApplicationContext applicationContext: [String: Any]) {
            // Latest-wins: `updateApplicationContext` transmits the sender's full
            // set, so the received array is authoritative. Replacing (rather than
            // unioning) local values makes a "clear" update ([]) propagate.
            // ReminderStore.reload() prunes stale skip IDs on the next fetch.
            // The two keys are independent — pushSkipIDs and
            // pushExcludedProjectTitles each send a separate application context,
            // so one key may be present without the other.
            if let receivedIDs = applicationContext[PayloadKey.skippedReminderIdentifiers] as? [String] {
                skipStore.save(receivedIDs)
            }
            if let receivedTitles = applicationContext[PayloadKey.excludedProjectTitles] as? [String] {
                excludeStore.save(receivedTitles)
            }
        }

        public func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            guard let identifier = message[PayloadKey.completeReminderIdentifier] as? String else { return }
            let handler = onCompleteReminderReceived
            handler?(identifier)
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
        }

        private static let logger = Logger(subsystem: "app.alanvardy.SingleThread", category: "ReminderSync")

        private let session: any SkipSyncSession
        private let skipStore: SkippedReminderStore
        private let excludeStore: ExcludedProjectStore
    }
#endif
