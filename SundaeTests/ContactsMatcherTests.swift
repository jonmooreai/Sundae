import Foundation
import Testing
@testable import Sundae

struct ContactsMatcherTests {
    @Test func normalizesNationalNumbersWithTheRegionCode() {
        #expect(ContactsMatcher.normalize("(317) 555-0142", region: "US") == "13175550142")
        #expect(ContactsMatcher.normalize("1 317 555 0142", region: "US") == "13175550142")
        #expect(ContactsMatcher.normalize("07700 900123", region: "GB") == "447700900123")
        #expect(ContactsMatcher.normalize("+44 7700 900123", region: "US") == "447700900123")
        #expect(ContactsMatcher.normalize("00 44 7700 900123", region: "US") == "447700900123")
    }

    @Test func dropsNumbersItCannotNormalizeConfidently() {
        #expect(ContactsMatcher.normalize("555-0142", region: "US") == nil)
        #expect(ContactsMatcher.normalize("12345", region: "US") == nil)
        #expect(ContactsMatcher.normalize("0176 12345678", region: "XX") == nil)
    }

    @Test func hashesAreKeyedAndStable() {
        let key = Data(repeating: 0x42, count: 32)
        let otherKey = Data(repeating: 0x43, count: 32)
        let a = ContactsMatcher.hash("13175550142", key: key)
        #expect(a == ContactsMatcher.hash("13175550142", key: key))
        #expect(a != ContactsMatcher.hash("13175550142", key: otherKey))
        #expect(a.count == 64)
        #expect(!a.contains("3175550142"))
    }
}
