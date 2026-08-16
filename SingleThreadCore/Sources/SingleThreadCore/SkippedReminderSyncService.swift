import Foundation

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

        public init(session: any SkipSyncSession, skipStore: SkippedReminderStore) {
            self.session = session
            self.skipStore = skipStore
            super.init()
        }

        // MARK: Public

        /// Hook invoked on the iPhone when the watch asks to complete a reminder.
        /// Passes the completed reminder's identifier. Written once from the main
        /// actor before `activate()` is called; read from WCSession's delegate
        /// queue (a non-main serial queue) thereafter.
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
                try session.updateApplicationContext(["skippedReminderIdentifiers": ids])
            } catch {
                print("Failed to push skip IDs: \(error)")
            }
        }

        /// Ask the iPhone to complete a reminder (watch-side action).
        public func requestCompleteReminder(_ identifier: String) {
            session.sendMessage(
                ["completeReminderIdentifier": identifier],
                replyHandler: nil) { error in
                    print("Failed to send completion request: \(error)")
                }
        }

        // MARK: WCSessionDelegate

        public func session(
            _: WCSession,
            didReceiveApplicationContext applicationContext: [String: Any]) {
            guard let receivedIDs = applicationContext["skippedReminderIdentifiers"] as? [String] else { return }
            // Merge with local IDs; resolve prunes stale entries next time reload runs.
            let localIDs = skipStore.load()
            let merged = Array(Set(localIDs + receivedIDs))
            skipStore.save(merged)
        }

        public func session(_: WCSession, didReceiveMessage message: [String: Any]) {
            guard let identifier = message["completeReminderIdentifier"] as? String else { return }
            let handler = onCompleteReminderReceived
            handler?(identifier)
        }

        public func session(
            _: WCSession,
            activationDidCompleteWith _: WCSessionActivationState,
            error: (any Error)?) {
            if let error {
                print("WCSession activation failed: \(error)")
            }
        }

        #if os(iOS)
            public func sessionDidBecomeInactive(_: WCSession) {}
            public func sessionDidDeactivate(_ wcSession: WCSession) {
                wcSession.activate()
            }
        #endif

        // MARK: Private

        private let session: any SkipSyncSession
        private let skipStore: SkippedReminderStore
    }
#endif
