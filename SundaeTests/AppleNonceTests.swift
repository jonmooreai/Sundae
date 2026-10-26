import Foundation
import Testing
@testable import Sundae

/// The server recomputes the hash Apple signed, so the two have to agree byte for byte.
struct AppleNonceTests {
    @Test func hashMatchesTheStandardVector() {
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func eachAttemptGetsANewLongNonce() {
        let nonces = Set((0..<50).map { _ in AppleNonce.make() })
        #expect(nonces.count == 50)
        #expect(nonces.allSatisfy { $0.count == 43 && !$0.contains("=") && !$0.contains("+") && !$0.contains("/") })
    }
}
