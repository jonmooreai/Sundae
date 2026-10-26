import CryptoKit
import Foundation

/// A one-time value for each Sign in with Apple attempt. Apple is given its SHA-256 and signs
/// that into the identity token; the server gets the nonce itself, checks the pair, and accepts
/// each nonce once. So a token copied off the network or out of a log cannot sign anyone in.
enum AppleNonce {
    /// 32 random bytes as URL-safe text. `SystemRandomNumberGenerator` is the system's
    /// cryptographic generator on Apple platforms.
    nonisolated static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// What Apple is given: the nonce's SHA-256 as lowercase hex, which the server recomputes.
    nonisolated static func sha256(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
