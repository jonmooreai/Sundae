import Foundation

/// Access and refresh tokens, in the Keychain with the this-device-only class.
///
/// Access tokens are short-lived (15 minutes). Refresh tokens rotate on every use and the
/// server revokes the whole family on reuse, so a stolen refresh token is good for one call
/// at most and burns the real session when it is tried.
struct TokenStore: Sendable {
    private enum Key {
        static let access = "auth.access"
        static let refresh = "auth.refresh"
        static let expiry = "auth.expiry"
    }

    var accessToken: String? { Keychain.string(for: Key.access) }
    var refreshToken: String? { Keychain.string(for: Key.refresh) }
    var accessExpiry: Date? {
        Keychain.string(for: Key.expiry).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    var hasSession: Bool { refreshToken != nil }

    func store(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
        Keychain.set(accessToken, for: Key.access)
        Keychain.set(refreshToken, for: Key.refresh)
        Keychain.set(String(Date().addingTimeInterval(expiresIn).timeIntervalSince1970), for: Key.expiry)
    }

    func clear() {
        Keychain.delete(Key.access)
        Keychain.delete(Key.refresh)
        Keychain.delete(Key.expiry)
    }
}
