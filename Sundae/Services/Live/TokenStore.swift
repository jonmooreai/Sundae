import Foundation
import Synchronization

/// Where tokens are kept. The Keychain in the app; memory in tests and unsigned CI builds,
/// where the Keychain refuses writes.
protocol SecretStorage: Sendable {
    func set(_ value: String, for key: String)
    func string(for key: String) -> String?
    func delete(_ key: String)
}

struct KeychainStorage: SecretStorage {
    func set(_ value: String, for key: String) { Keychain.set(value, for: key) }
    func string(for key: String) -> String? { Keychain.string(for: key) }
    func delete(_ key: String) { Keychain.delete(key) }
}

final class InMemorySecretStorage: SecretStorage {
    private let values = Mutex<[String: String]>([:])
    init() {}
    func set(_ value: String, for key: String) { values.withLock { $0[key] = value } }
    func string(for key: String) -> String? { values.withLock { $0[key] } }
    func delete(_ key: String) { _ = values.withLock { $0.removeValue(forKey: key) } }
}

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

    private let storage: any SecretStorage

    init(storage: any SecretStorage = KeychainStorage()) {
        self.storage = storage
    }

    var accessToken: String? { storage.string(for: Key.access) }
    var refreshToken: String? { storage.string(for: Key.refresh) }
    var accessExpiry: Date? {
        storage.string(for: Key.expiry).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    var hasSession: Bool { refreshToken != nil }

    func store(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
        storage.set(accessToken, for: Key.access)
        storage.set(refreshToken, for: Key.refresh)
        storage.set(String(Date().addingTimeInterval(expiresIn).timeIntervalSince1970), for: Key.expiry)
    }

    func clear() {
        storage.delete(Key.access)
        storage.delete(Key.refresh)
        storage.delete(Key.expiry)
    }
}
