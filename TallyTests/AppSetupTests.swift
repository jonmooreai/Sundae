import Foundation
import Testing
@testable import Tally

/// The privacy details the app carries, and the fresh-install check that keeps a phone's previous
/// owner from being signed back in.
struct AppSetupTests {
    @Test func theAppCarriesThePrivacyDetails() throws {
        let policy = try #require(PrivacyPolicy.bundled())
        #expect(!policy.summary.isEmpty)
        #expect(!policy.sections.isEmpty)
        #expect(policy.sections.allSatisfy { !$0.items.isEmpty && $0.items.allSatisfy { !$0.isEmpty } })
        #expect(!policy.updatedLabel.contains("-"))
    }

    private func emptyDefaults() throws -> UserDefaults {
        let name = "AppSetupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func aFreshInstallIsFreshOnlyOnce() throws {
        let defaults = try emptyDefaults()
        #expect(FreshInstall.check(defaults, evidence: ["session.user"]))
        #expect(!FreshInstall.check(defaults, evidence: ["session.user"]))
    }

    /// Someone signed in on a build from before the flag keeps their session.
    @Test func anUpdateFromBeforeTheFlagIsNotFresh() throws {
        let defaults = try emptyDefaults()
        defaults.set(Data("{}".utf8), forKey: "session.user")
        #expect(!FreshInstall.check(defaults, evidence: ["session.user"]))
    }
}
