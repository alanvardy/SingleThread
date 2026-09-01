import Foundation
import SingleThreadCore
import Testing

// MARK: - AppInfo Tests

struct AppInfoTests {
    @Test
    func readsMarketingVersionBuildNumberAndDisplayName() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleDisplayName": "SingleThread"
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == "1")
        #expect(info.displayName == "SingleThread")
        #expect(info.versionDescription == String.en(
            "Version \(info.marketingVersion!) (\(info.buildNumber!))",
            bundle: .core))
    }

    @Test
    func fallsBackWhenIdentityKeysAreAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [:]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == nil)
        #expect(info.displayName == "SingleThread")
        #expect(info.versionDescription.isEmpty)
    }

    @Test
    func omitsBuildParentheticalWhenBuildIsAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleShortVersionString": "1.0"
        ]))

        #expect(info.marketingVersion == "1.0")
        #expect(info.buildNumber == nil)
        #expect(info.versionDescription == String.en(
            "Version \(info.marketingVersion!)",
            bundle: .core))
    }

    @Test
    func emptyVersionWhenMarketingAbsentButBuildPresent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleVersion": "1"
        ]))

        #expect(info.marketingVersion == nil)
        #expect(info.buildNumber == "1")
        #expect(info.versionDescription.isEmpty)
    }

    @Test
    func fallsBackToBundleNameWhenDisplayNameAbsent() {
        let info = AppInfo(bundle: StubBundle(info: [
            "CFBundleName": "SingleThread"
        ]))

        #expect(info.displayName == "SingleThread")
    }
}
