import Foundation
import Testing
@testable import Sundae

/// The bits of push notifications that can be checked without a phone: which of Apple's two
/// services a build belongs to, and when the switches in Settings call for iOS's permission.
struct PushTests {
    @Test func aDevelopmentProfileMeansTheSandboxAndAnythingElseProduction() {
        let development = "<plist><dict><key>aps-environment</key>\n\t<string>development</string></dict></plist>"
        let production = "<plist><dict><key>aps-environment</key>\n\t<string>production</string></dict></plist>"
        #expect(PushEnvironment.isSandbox(profile: development))
        #expect(!PushEnvironment.isSandbox(profile: production))
        #expect(!PushEnvironment.isSandbox(profile: "<plist><dict></dict></plist>"), "no entitlement: TestFlight and the App Store")
        #expect(!PushEnvironment.isSandbox(profile: "development <key>aps-environment</key><string>production</string>"), "only the value after the key counts")
    }

    @Test func anySwitchOnWantsNotificationsAndTurningOneOnIsTheMomentToAsk() {
        var settings = AccountSettings()
        #expect(settings.wantsAnyNotification, "on by default")
        settings.notifySundayReminder = false
        settings.notifyLastCall = false
        settings.notifyTags = false
        settings.notifyFollowRequests = false
        settings.notifyLikesAndComments = false
        settings.notifyTagApproved = false
        #expect(!settings.wantsAnyNotification)
        var wanted = settings
        wanted.notifyLikesAndComments = true
        #expect(wanted.wantsAnyNotification)
        #expect(wanted.turnedOnANotification(since: settings))
        #expect(!settings.turnedOnANotification(since: wanted), "turning one off is not")
        #expect(!wanted.turnedOnANotification(since: wanted))
    }

    @Test func aNotificationCarriesWhatTheAppOpens() {
        let info = PushInfo(["kind": "comment", "dump_id": "d_123", "aps": ["alert": "x"]])
        #expect(info.kind == "comment")
        #expect(info.dumpID == "d_123")
        #expect(info.userID == nil)
        #expect(PushInfo([:]).kind == "")
    }
}
