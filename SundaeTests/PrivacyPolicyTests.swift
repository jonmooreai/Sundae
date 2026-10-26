import Foundation
import Testing
@testable import Sundae

/// The Privacy screen reads Shared/privacy.json from the app bundle, the same file the server's
/// /privacy page is built from. If it goes missing, the screen has nothing to show.
struct PrivacyPolicyTests {
    @Test func theAppCarriesThePrivacyDetails() throws {
        let policy = try #require(PrivacyPolicy.bundled())
        #expect(!policy.summary.isEmpty)
        #expect(policy.sections.contains { $0.title == "What Sundae never collects" })
        #expect(policy.sections.allSatisfy { !$0.items.isEmpty && $0.items.allSatisfy { !$0.isEmpty } })
        #expect(policy.sections.flatMap(\.items).contains { $0.contains("contacts") })
    }

    @Test func theDateReadsLikeADate() throws {
        let policy = try #require(PrivacyPolicy.bundled())
        #expect(!policy.updatedLabel.contains("-"))
    }
}
