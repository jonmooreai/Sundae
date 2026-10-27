import Foundation

/// What the share sheet sends when someone invites a friend. No link: Sundae is in TestFlight,
/// and only the person who runs it can add testers, so the note asks to be added instead.
enum Invite {
    static let subject = "Join me on Sundae"
    static let note = "I'm on Sundae. A few of us share our week in photos, and it only opens on Sundays. It's invite only while it's being tested. Want in? Tell me and I'll get you added."
}
