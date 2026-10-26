import Foundation
import Security

/// A small key-value store the app and the widget both read.
///
/// With an app group configured it is that group's defaults. Without one (the current builds),
/// it is a single keychain item in a shared access group, which every provisioning profile
/// already allows through its `TEAMID.*` keychain wildcard, so no portal setup is needed.
/// If the keychain is unavailable (an unsigned simulator build), it falls back to this
/// process's own defaults, which is how things worked before.
final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    private let suite: UserDefaults?
    private let accessGroup: String?
    private let lock = NSLock()
    private var keychainUnavailable = false

    private static let service = "com.jonmooreai.sundae.shared"
    private static let account = "state"

    init(appGroup: String? = SharedDefaults.configuredAppGroup,
         accessGroup: String? = SharedStore.configuredAccessGroup) {
        suite = appGroup.flatMap { UserDefaults(suiteName: $0) }
        self.accessGroup = accessGroup
    }

    /// `SundaeKeychainGroup` in Info.plist, `$(AppIdentifierPrefix)com.jonmooreai.sundae.shared`.
    /// Unsigned builds leave the prefix empty; the keychain then refuses and the fallback is used.
    static var configuredAccessGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SundaeKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix("com.") else { return nil }
        return group
    }

    // MARK: UserDefaults-shaped access

    func object(forKey key: String) -> Any? {
        if let suite { return suite.object(forKey: key) }
        lock.lock(); defer { lock.unlock() }
        if useFallback { return UserDefaults.standard.object(forKey: key) }
        return read()[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let suite { suite.set(value, forKey: key); return }
        lock.lock(); defer { lock.unlock() }
        if useFallback { UserDefaults.standard.set(value, forKey: key); return }
        var state = read()
        state[key] = value
        if !write(state) {
            keychainUnavailable = true
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    func removeObject(forKey key: String) { set(nil, forKey: key) }
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    func integer(forKey key: String) -> Int { (object(forKey: key) as? Int) ?? 0 }

    // MARK: Keychain

    private var useFallback: Bool { accessGroup == nil || keychainUnavailable }

    private var baseQuery: [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: Self.account,
            kSecUseDataProtectionKeychain: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup] = accessGroup }
        return query
    }

    private func read() -> [String: Any] {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecMissingEntitlement { keychainUnavailable = true }
        guard status == errSecSuccess, let data = item as? Data,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    /// The whole dictionary as one property list. Readable after first unlock, so the widget can
    /// draw on the Lock Screen and in StandBy.
    private func write(_ state: [String: Any]) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0) else { return false }
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(update) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}
