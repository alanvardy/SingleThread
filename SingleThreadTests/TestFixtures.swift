import EventKit
@testable import SingleThread
import SingleThreadCore
import Speech

// MARK: - Shared EKEventStore + reminder builders

/// A single `EKEventStore` kept alive to back the test reminders. The backing
/// store must outlive the reminders — `EKReminder` holds a weak reference to
/// it, so a deallocated store crashes (SIGTRAP) when any property is read.
@MainActor let sharedTestEventStore = EKEventStore()

/// Construction only — never saved through EventKit.
@MainActor
func makeReminder(
    title: String,
    priority: Int = 0,
    dateComponents: DateComponents? = nil) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    reminder.priority = priority
    reminder.dueDateComponents = dateComponents
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
func makeReminder(title: String, calendarTitle: String) -> EKReminder {
    let reminder = EKReminder(eventStore: sharedTestEventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = calendarTitle
    reminder.calendar = calendar
    return reminder
}

/// Construction only — never saved through EventKit.
@MainActor
func makeCalendar(title: String) -> EKCalendar {
    let calendar = EKCalendar(for: .reminder, eventStore: sharedTestEventStore)
    calendar.title = title
    return calendar
}

/// Builds a reminder that lives in a calendar titled `list`, so exclusion
/// filtering (which matches `calendar.title`) can be exercised.
/// Construction only — never saved through EventKit.
@MainActor
func inListReminder(title: String, list: String) -> EKReminder {
    let eventStore = EKEventStore()
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = list
    reminder.calendar = calendar
    return reminder
}

// MARK: - Fake sync session

// `SkipSyncSession` comes from the WatchConnectivity framework, which is
// iOS/watchOS-only; the entire sync-test surface that consumes `FakeSession` is
// guarded behind the same `#if` (see SkippedReminderSyncServiceTests.swift).
#if os(iOS) || os(watchOS)
    import WatchConnectivity

    final class FakeSession: SkipSyncSession {
        var activated = false
        var lastContext: [String: Any]?
        var lastMessage: [String: Any]?
        var pushShouldThrow = false

        func activate() {
            activated = true
        }

        func updateApplicationContext(_ applicationContext: [String: Any]) throws {
            if pushShouldThrow {
                throw NSError(domain: "test", code: 1)
            }
            lastContext = applicationContext
        }

        func sendMessage(
            _ message: [String: Any],
            replyHandler _: (([String: Any]) -> Void)?,
            errorHandler _: ((any Error) -> Void)?) {
            lastMessage = message
        }
    }
#endif

// MARK: - Fake transcriber

/// Superset of the three former per-file fakes (`MicToggleFakeTranscriber`,
/// `ActionButtonFakeTranscriber`, `GlowFakeTranscriber`). Their
/// `requestAuthorization`/`transcribe` bodies were textually identical; this
/// keeps the full surface (`refreshCallCount`, `liveStatus`) so every former
/// consumer compiles unchanged.
@MainActor
final class TestFakeTranscriber: SpeechTranscribing {
    // MARK: Lifecycle

    init(authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .authorized) {
        self.authorizationStatus = authorizationStatus
        liveStatus = authorizationStatus
    }

    // MARK: Internal

    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    /// The status `refreshAuthorizationStatus()` re-reads — the test mutates
    /// this to simulate a Settings change while the app is backgrounded.
    var liveStatus: SFSpeechRecognizerAuthorizationStatus

    private(set) var refreshCallCount = 0

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        authorizationStatus
    }

    func refreshAuthorizationStatus() {
        refreshCallCount += 1
        authorizationStatus = liveStatus
    }

    func transcribe(
        onPartialResult _: @escaping @MainActor (String) -> Void) async throws -> String {
        ""
    }
}

// MARK: - Background-fetcher fakes

final class FakeBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    private(set) var requestedURLs: [URL] = []
    var stubbedData: [URL: Result<Data, Error>] = [:]

    func fetchData(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return try stubbedData[url]!.get()
    }
}

/// One-shot rendezvous that parks a fetch in-flight so a test can observe
/// `isRefreshing` before releasing it.
actor FetchGate {
    // MARK: Internal

    func wait() async {
        if wasHit {
            return
        }
        wasHit = true
        hitSignal?.resume()
        await withCheckedContinuation { parked = $0 }
    }

    func waitUntilHit() async {
        if wasHit {
            return
        }
        await withCheckedContinuation { hitSignal = $0 }
    }

    func open() {
        parked?.resume()
        parked = nil
    }

    // MARK: Private

    private var parked: CheckedContinuation<Void, Never>?
    private var hitSignal: CheckedContinuation<Void, Never>?
    private var wasHit = false
}

/// Parks the first (endpoint) fetch behind a gate, then serves valid data.
final class GatedBackgroundFetcher: BackgroundImageFetching, @unchecked Sendable {
    // MARK: Lifecycle

    init(endpointURL: URL) {
        self.endpointURL = endpointURL
    }

    // MARK: Internal

    let gate = FetchGate()
    var endpointData: Data = .init()
    var imageData: Data = .init()

    func fetchData(from url: URL) async throws -> Data {
        let isEndpoint = url == endpointURL
        if isEndpoint {
            await gate.wait()
        }
        return isEndpoint ? endpointData : imageData
    }

    // MARK: Private

    private let endpointURL: URL
}

/// Serves the store's endpoint payload and photo so tests can seed a populated
/// store without touching the network.
final class SeededFetcher: BackgroundImageFetching, @unchecked Sendable {
    // MARK: Internal

    func fetchData(from url: URL) async throws -> Data {
        if url == Self.endpoint {
            let json = "{\"url\":\"\(Self.imageURL.absoluteString)\",\"photographer\":\"NEOM\","
                + "\"photographer_url\":\"https://unsplash.com/@neom\"}"
            return Data(json.utf8)
        }
        return BackgroundTestFixtures.jpegData
    }

    // MARK: Private

    private static let endpoint = URL(string: "https://vardy.cc/unsplash")!
    private static let imageURL = URL(string: "https://images.unsplash.com/photo-1.jpg")!
}
