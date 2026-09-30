import Foundation
@testable import SingleThread
import Testing

@MainActor
struct SentryConfigurationTests {
    @Test
    func dsnIsTrimmedAndKept() {
        let config = SentryConfiguration.make(dsn: "  https://a@b.ingest.sentry.io/1  ", environment: "debug")
        #expect(config?.dsn == "https://a@b.ingest.sentry.io/1")
    }

    @Test
    func emptyDsnYieldsNil() {
        #expect(SentryConfiguration.make(dsn: nil, environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "", environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "   \n", environment: "debug") == nil)
    }

    @Test
    func emptyDsnIsNeverStarted() {
        // Whitespace-only and missing DSNs must all yield `nil` so `SentryBootstrap`
        // never calls `SentrySDK.start`. A non-String Info.plist value is already
        // drained by the `bundleDSN` call site's `as? String` cast (yielding `nil`),
        // so `make`'s `String?` signature cannot observe it.
        #expect(SentryConfiguration.make(dsn: "   ", environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "\n\t", environment: "debug") == nil)
        #expect(SentryConfiguration.make(dsn: "\r\n \t", environment: "debug") == nil)
    }

    @Test
    func privacyDefaultsAreSafe() {
        let config = SentryConfiguration.make(dsn: "https://a@b.ingest.sentry.io/1", environment: "production")
        #expect(config?.sendDefaultPii == false)
        #expect(config?.tracesSampleRate == 0)
        #expect((config?.maxBreadcrumbs ?? 0) > 0 && (config?.maxBreadcrumbs ?? .max) <= 50)
    }

    @Test
    func environmentMapsDebugBuild() {
        #if DEBUG
            #expect(SentryConfiguration.currentEnvironment == "debug")
        #else
            #expect(SentryConfiguration.currentEnvironment == "production")
        #endif
    }
}
