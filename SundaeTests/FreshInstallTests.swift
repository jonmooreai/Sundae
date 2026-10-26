import Foundation
import Testing
@testable import Sundae

/// A fresh install clears a session the Keychain kept from before; an update never does.
struct FreshInstallTests {
    private func emptyDefaults() throws -> UserDefaults {
        let name = "FreshInstallTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFreshInstallIsFreshOnlyOnce() throws {
        let defaults = try emptyDefaults()
        #expect(FreshInstall.check(defaults, evidence: ["session.user", "appearance"]))
        #expect(!FreshInstall.check(defaults, evidence: ["session.user", "appearance"]))
        #expect(defaults.bool(forKey: FreshInstall.flag))
    }

    /// Someone signed in on a build from before the flag keeps their session.
    @Test func anUpdateFromBeforeTheFlagIsNotFresh() throws {
        let defaults = try emptyDefaults()
        defaults.set(Data("{}".utf8), forKey: "session.user")
        #expect(!FreshInstall.check(defaults, evidence: ["session.user", "appearance"]))
        #expect(defaults.bool(forKey: FreshInstall.flag))
    }

    @Test func anyEvidenceCounts() throws {
        let defaults = try emptyDefaults()
        defaults.set("dark", forKey: "appearance")
        #expect(!FreshInstall.check(defaults, evidence: ["session.user", "appearance"]))
    }
}
