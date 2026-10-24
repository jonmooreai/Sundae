import Contacts
import CryptoKit
import Foundation
import Observation

/// Finds friends already on Sundae from the address book without uploading the address book.
///
/// Phone numbers are normalized on device, hashed with HMAC-SHA256 under a per-session key
/// from the server, and only the hashes travel. The server matches in memory and discards them.
/// Opt in, never automatic, and the choice is remembered locally only.
@MainActor
@Observable
final class ContactsMatcher {
    private let api: any SundaeAPI
    private(set) var matches: [User] = []
    private(set) var isMatching = false
    private(set) var authorization = CNContactStore.authorizationStatus(for: .contacts)
    var errorMessage: String?

    private static let optInKey = "contacts.optedIn"

    init(api: any SundaeAPI) {
        self.api = api
    }

    var isOptedIn: Bool {
        get { UserDefaults.standard.bool(forKey: Self.optInKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.optInKey) }
    }

    var canUse: Bool {
        authorization == .authorized || authorization == .limited || authorization == .notDetermined
    }

    /// Asks for Contacts access if needed, hashes the numbers, and asks the server who is here.
    func match() async {
        guard !isMatching else { return }
        isMatching = true
        defer { isMatching = false }
        errorMessage = nil

        if authorization == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
            authorization = CNContactStore.authorizationStatus(for: .contacts)
        }
        guard authorization == .authorized || authorization == .limited else {
            errorMessage = "Sundae can't see your contacts. You can allow it in Settings."
            return
        }

        do {
            // Enumerating a large address book is slow; keep it off the main actor.
            let numbers = try await Task.detached(priority: .userInitiated) {
                try Self.phoneNumbers(from: CNContactStore())
            }.value
            guard !numbers.isEmpty else {
                matches = []
                return
            }
            let key = try await api.contactsHashingKey()
            let hashes = numbers.map { Self.hash($0, key: key.key) }
            matches = try await api.matchContacts(hashes: hashes, keyID: key.keyID)
            isOptedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Hashing

    /// HMAC-SHA256 over the normalized number, hex encoded.
    nonisolated static func hash(_ normalizedNumber: String, key: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(normalizedNumber.utf8), using: SymmetricKey(data: key))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Digits only, with a country calling code in front. Numbers that already carry a "+"
    /// are trusted; bare national numbers get the device region's code where we know it.
    /// Numbers that cannot be normalized confidently are dropped rather than sent wrong.
    nonisolated static func normalize(_ raw: String, region: String? = Locale.current.region?.identifier) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return nil }
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return digits }
        if digits.hasPrefix("00"), digits.count > 9 { return String(digits.dropFirst(2)) }
        guard let code = callingCodes[region ?? ""] else { return nil }
        var national = digits
        if national.hasPrefix("0") && code != "1" { national.removeFirst() }
        if code == "1" {
            if national.count == 11, national.hasPrefix("1") { return national }
            guard national.count == 10 else { return nil }
        }
        return code + national
    }

    private nonisolated static func phoneNumbers(from store: CNContactStore) throws -> [String] {
        let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        var numbers = Set<String>()
        try store.enumerateContacts(with: request) { contact, _ in
            for phone in contact.phoneNumbers {
                if let normalized = normalize(phone.value.stringValue) { numbers.insert(normalized) }
            }
        }
        return numbers.sorted()
    }

    /// Regions where the beta cohort lives. Extend as the app launches elsewhere.
    private nonisolated static let callingCodes: [String: String] = [
        "US": "1", "CA": "1", "GB": "44", "IE": "353", "AU": "61", "NZ": "64", "DE": "49", "FR": "33",
        "ES": "34", "IT": "39", "NL": "31", "BE": "32", "SE": "46", "NO": "47", "DK": "45", "FI": "358",
        "PT": "351", "CH": "41", "AT": "43", "PL": "48", "JP": "81", "KR": "82", "IN": "91", "BR": "55",
        "MX": "52", "AR": "54", "ZA": "27", "SG": "65", "PH": "63",
    ]
}
