import SwiftUI
import UserNotifications

/// What a notification carried, in the few fields the app acts on.
struct PushInfo: Sendable, Hashable {
    var kind: String
    var dumpID: String?
    var userID: String?

    init(_ userInfo: [AnyHashable: Any]) {
        kind = userInfo["kind"] as? String ?? ""
        dumpID = userInfo["dump_id"] as? String
        userID = userInfo["user_id"] as? String
    }
}

/// Where iOS hands over this phone's push token, and the notification someone tapped. The app
/// delegate exists for these two things only; everything else is SwiftUI.
@MainActor
final class PushDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokens.shared.received(deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // The simulator, or no connection yet: nothing to keep. The next open asks again.
    }

    /// A banner even while Sundae is open, so a comment arriving mid-scroll is still seen, and
    /// the Notifications tab's count moves with it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let info = PushInfo(notification.request.content.userInfo)
        await MainActor.run { PushTokens.shared.arrived(info) }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = PushInfo(response.notification.request.content.userInfo)
        await MainActor.run { PushTokens.shared.opened(info) }
    }
}

/// The token and the taps, kept until the model listens and handed over after. One per app.
@MainActor
final class PushTokens {
    static let shared = PushTokens()

    /// The latest token iOS gave this phone, hex, as Apple's servers want it.
    private(set) var token: String?
    private var pendingOpen: PushInfo?
    var onToken: (@MainActor (String) -> Void)?
    var onArrived: (@MainActor (PushInfo) -> Void)?
    var onOpen: (@MainActor (PushInfo) -> Void)?

    func received(_ token: String) {
        self.token = token
        onToken?(token)
    }

    func arrived(_ info: PushInfo) {
        onArrived?(info)
    }

    func opened(_ info: PushInfo) {
        if let onOpen { onOpen(info) } else { pendingOpen = info }
    }

    /// A notification tapped before the model was listening, once.
    func takePendingOpen() -> PushInfo? {
        defer { pendingOpen = nil }
        return pendingOpen
    }
}

/// Which of Apple's two push services this build's tokens belong to. A build Xcode installs is
/// signed for development and its tokens work only on the sandbox; TestFlight and the App Store
/// are production. The provisioning profile in the app says which.
enum PushEnvironment {
    static var current: String { isSandbox ? "sandbox" : "production" }

    static var isSandbox: Bool {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path) else { return false }
        return isSandbox(profile: String(decoding: data, as: UTF8.self))
    }

    /// The profile is a signed binary with its plist inside as text; the entitlement's value
    /// follows its key within a few bytes.
    static func isSandbox(profile: String) -> Bool {
        guard let key = profile.range(of: "<key>aps-environment</key>") else { return false }
        return profile[key.upperBound...].prefix(80).contains("development")
    }
}
