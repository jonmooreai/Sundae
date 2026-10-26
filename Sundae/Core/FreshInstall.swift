import Foundation

/// Deleting the app empties UserDefaults but leaves the Keychain, so a fresh install could
/// otherwise open signed in as whoever used the phone before. This tells a fresh install
/// from an update, once, so the first launch can clear what was left behind.
enum FreshInstall {
    static let flag = "install.seen"

    /// True on the first launch of a fresh install, false ever after. An install without the
    /// flag that still has any of `evidence` (left by an earlier launch, such as the cached
    /// account) is an update from before the flag, and keeps its session.
    static func check(_ defaults: UserDefaults, evidence: [String]) -> Bool {
        if defaults.bool(forKey: flag) { return false }
        defaults.set(true, forKey: flag)
        return !evidence.contains { defaults.object(forKey: $0) != nil }
    }
}
