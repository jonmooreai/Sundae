import Foundation

typealias ID = String

/// Where a photo's pixels come from. Remote URLs are short-lived signed URLs from the server.
/// `data` is a processed JPEG that has not been uploaded yet (or a mock photo).
/// `placeholder` draws a soft gradient and exists only for seed data and previews.
enum PhotoSource: Hashable, Codable, Sendable {
    case remote(URL)
    case data(Data)
    case placeholder(seed: Int)
}

struct User: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var username: String
    var name: String
    var bio: String
    var avatar: PhotoSource?
    var isPublic: Bool
    var timezone: String
    /// Usernames of people the viewer follows who follow this user. Search and suggestions only.
    var followedBy: [String]? = nil
    /// "MM-DD", shared with friends only when the user allows it. Never a year.
    var birthday: String? = nil
    /// True when this user joined from the viewer's invite link.
    var invitedByMe: Bool? = nil
    /// Only ever set on your own account, and only for admins (docs/SERVER.md).
    var isAdmin: Bool? = nil

    var displayName: String { name.isEmpty ? username : name }
    /// "Bob Ewing • Followed by parker + 2", one line.
    var searchSubtitle: String {
        var parts: [String] = []
        if !name.isEmpty { parts.append(name) }
        if let followedBy, let first = followedBy.first {
            parts.append(followedBy.count > 1 ? "Followed by \(first) + \(followedBy.count - 1)" : "Followed by \(first)")
        }
        return parts.joined(separator: " \u{2022} ")
    }
    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? displayName }
    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct Tag: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case pending, approved, declined, removed }
    var id: ID
    var photoID: ID
    var taggerID: ID
    var taggedUser: User
    var status: Status
    var respondedAt: Date?
}

struct Photo: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var dumpID: ID
    var order: Int
    var source: PhotoSource
    var width: Int
    var height: Int
    var altText: String?
    var tags: [Tag]

    var aspectRatio: CGFloat { height == 0 ? 1 : CGFloat(width) / CGFloat(height) }
    /// Tags that should be drawn: pending and approved. Declined and removed tags vanish everywhere.
    var visibleTags: [Tag] { tags.filter { $0.status == .pending || $0.status == .approved } }
}

struct Dump: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var author: User
    var weekStart: Date
    var caption: String
    var createdAt: Date
    var lockedAt: Date?
    var photos: [Photo]
    var commentsEnabled: Bool
    var likedBy: [User]
    var likedByMe: Bool
    var commentCount: Int
    /// True for the author's first week ever. Friends see a small card for it.
    var isAuthorsFirst: Bool? = nil

    var isLocked: Bool { lockedAt != nil }
    /// Everyone tagged anywhere in the dump, once each, for the "with Maya, Theo" line.
    var taggedUsers: [User] {
        var seen = Set<ID>()
        return photos.flatMap(\.visibleTags).map(\.taggedUser).filter { seen.insert($0.id).inserted }
    }
}

struct Comment: Identifiable, Hashable, Codable, Sendable {
    var id: ID
    var dumpID: ID
    var author: User
    var body: String
    var createdAt: Date
    var editedAt: Date?
    var likeCount: Int
    var likedByMe: Bool

    init(id: ID, dumpID: ID, author: User, body: String, createdAt: Date,
         editedAt: Date? = nil, likeCount: Int = 0, likedByMe: Bool = false) {
        self.id = id
        self.dumpID = dumpID
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.likeCount = likeCount
        self.likedByMe = likedByMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ID.self, forKey: .id)
        dumpID = try c.decode(ID.self, forKey: .dumpID)
        author = try c.decode(User.self, forKey: .author)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        likedByMe = try c.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
    }
}

struct Follow: Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case requested, accepted }
    var followerID: ID
    var followeeID: ID
    var status: Status
}

enum Relationship: Hashable, Sendable {
    case me
    case following
    case requested
    case notFollowing
    case blocked
}

/// A tag request as the tagged person sees it in Approvals.
struct TagRequest: Identifiable, Hashable, Sendable {
    var tag: Tag
    var photo: Photo
    var tagger: User
    var weekStart: Date
    var id: ID { tag.id }
}

/// A photo that landed on someone's profile through an approved tag.
struct TaggedPhoto: Identifiable, Hashable, Sendable {
    var photo: Photo
    var from: User
    var tag: Tag
    var id: ID { tag.id }
}

struct ProfileWeek: Identifiable, Hashable, Sendable {
    var weekStart: Date
    var dump: Dump?
    var tagged: [TaggedPhoto]
    var id: Date { weekStart }
    var isEmpty: Bool { (dump?.photos.isEmpty ?? true) && tagged.isEmpty }
}

struct Profile: Hashable, Sendable {
    var user: User
    var relationship: Relationship
    var weeks: [ProfileWeek]
    /// Only populated when the viewer is the owner. Never shown publicly.
    var followerCount: Int?
    var followingCount: Int?
}

struct SuggestionDone: Hashable, Codable, Sendable {
    var suggestionID: String
    var doneOn: Date
}

/// A photo in the compose screen before it is posted.
struct DraftPhoto: Identifiable, Hashable, Codable, Sendable {
    var id: ID = UUID().uuidString
    var source: PhotoSource
    var width: Int
    var height: Int
    var taggedUsers: [User] = []
    var altText: String = ""
    var takenAt: Date?
}

struct DumpDraft: Hashable, Codable, Sendable {
    static let maxPhotos = 15
    static let maxTagsPerPhoto = 10
    static let maxCaptionLength = 300

    var photos: [DraftPhoto] = []
    var caption: String = ""
    var commentsEnabled: Bool = true

    var isEmpty: Bool { photos.isEmpty }
    var canAddMore: Bool { photos.count < Self.maxPhotos }
    var remainingSlots: Int { max(0, Self.maxPhotos - photos.count) }
}

struct Report: Hashable, Codable, Sendable {
    enum Target: String, Codable, Sendable { case photo, dump, comment, profile }
    enum Reason: String, Codable, Sendable, CaseIterable, Identifiable {
        case nudity, harassment, violence, spam, underage, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .nudity: "Nudity or sexual content"
            case .harassment: "Harassment or bullying"
            case .violence: "Violence or dangerous acts"
            case .spam: "Spam or scam"
            case .underage: "Someone under 16"
            case .other: "Something else"
            }
        }
    }
    var target: Target
    var targetID: ID
    var reason: Reason
    var note: String
}

/// Account-level settings that live on the server and follow the account across devices.
struct AccountSettings: Hashable, Codable, Sendable {
    var isPublic = false
    var autoApproveUserIDs: [ID] = []
    var commentsEnabled = true
    var hideChallenges = false
    var notifySundayReminder = true
    var notifyLastCall = true
    var notifyTags = true
    var notifyFollowRequests = true
    var notifyLikesAndComments = true
    var notifyTagApproved = false

    /// Auto-approved people who are not among `taggable`, the people who can tag you now: neither
    /// of you follows the other any more. Their old yes would count again if one of you followed.
    func autoApprovedIDs(notIn taggable: [User]) -> [ID] {
        let current = Set(taggable.map(\.id))
        return autoApproveUserIDs.filter { !current.contains($0) }
    }
}

/// Only the account settings that changed. Saving sends just these, so a copy of the settings
/// that went stale on another device or window can't undo what was saved there since.
struct AccountSettingsPatch: Hashable, Sendable {
    var isPublic: Bool?
    var autoApproveUserIDs: [ID]?
    var commentsEnabled: Bool?
    var hideChallenges: Bool?
    var notifySundayReminder: Bool?
    var notifyLastCall: Bool?
    var notifyTags: Bool?
    var notifyFollowRequests: Bool?
    var notifyLikesAndComments: Bool?
    var notifyTagApproved: Bool?

    init() {}

    /// The fields where `new` differs from `old`, with their new values.
    init(from old: AccountSettings, to new: AccountSettings) {
        if new.isPublic != old.isPublic { isPublic = new.isPublic }
        if new.autoApproveUserIDs != old.autoApproveUserIDs { autoApproveUserIDs = new.autoApproveUserIDs }
        if new.commentsEnabled != old.commentsEnabled { commentsEnabled = new.commentsEnabled }
        if new.hideChallenges != old.hideChallenges { hideChallenges = new.hideChallenges }
        if new.notifySundayReminder != old.notifySundayReminder { notifySundayReminder = new.notifySundayReminder }
        if new.notifyLastCall != old.notifyLastCall { notifyLastCall = new.notifyLastCall }
        if new.notifyTags != old.notifyTags { notifyTags = new.notifyTags }
        if new.notifyFollowRequests != old.notifyFollowRequests { notifyFollowRequests = new.notifyFollowRequests }
        if new.notifyLikesAndComments != old.notifyLikesAndComments { notifyLikesAndComments = new.notifyLikesAndComments }
        if new.notifyTagApproved != old.notifyTagApproved { notifyTagApproved = new.notifyTagApproved }
    }

    var isEmpty: Bool { self == AccountSettingsPatch() }

    /// `settings` with these fields changed and every other field left as it was.
    func applied(to settings: AccountSettings) -> AccountSettings {
        var result = settings
        if let isPublic { result.isPublic = isPublic }
        if let autoApproveUserIDs { result.autoApproveUserIDs = autoApproveUserIDs }
        if let commentsEnabled { result.commentsEnabled = commentsEnabled }
        if let hideChallenges { result.hideChallenges = hideChallenges }
        if let notifySundayReminder { result.notifySundayReminder = notifySundayReminder }
        if let notifyLastCall { result.notifyLastCall = notifyLastCall }
        if let notifyTags { result.notifyTags = notifyTags }
        if let notifyFollowRequests { result.notifyFollowRequests = notifyFollowRequests }
        if let notifyLikesAndComments { result.notifyLikesAndComments = notifyLikesAndComments }
        if let notifyTagApproved { result.notifyTagApproved = notifyTagApproved }
        return result
    }
}

struct Session: Hashable, Codable, Sendable {
    var token: String
    var user: User
}

enum SignInOutcome: Hashable, Sendable {
    /// An account already exists for this sign-in: everything set up before comes back.
    case signedIn(Session)
    /// Nobody has signed in this way before. The ticket creates their account, once.
    case newAccount(ticket: String)
}

enum SignInMethod: Hashable, Sendable {
    /// `nonce` is the one whose SHA-256 Apple signed into the token (AppleNonce).
    case apple(identityToken: String, fullName: String?, nonce: String)
    case phone(number: String, code: String)
    case demo
}

enum SundaeError: LocalizedError, Equatable {
    case sundayClosed
    case dumpLocked
    case tooManyPhotos
    case tooManyTags
    case captionTooLong
    case notAuthorized
    case notFound
    case offline
    case invalidCode
    case invalidPhoto
    case usernameTaken
    case invalidUsername
    case signupsClosed
    case signInAgain
    /// The server refused to renew the session: it was revoked, ran out or was used elsewhere.
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .sundayClosed: "The feed opens on Sunday."
        case .dumpLocked: "This week's dump is locked. Sunday is over."
        case .invalidPhoto: "That image could not be read."
        case .tooManyPhotos: "A dump holds up to \(DumpDraft.maxPhotos) photos."
        case .tooManyTags: "You can tag up to \(DumpDraft.maxTagsPerPhoto) people per photo."
        case .captionTooLong: "Captions are up to \(DumpDraft.maxCaptionLength) characters."
        case .notAuthorized: "You can't do that."
        case .notFound: "That's gone."
        case .offline: "You're offline. We'll keep your draft."
        case .invalidCode: "That code didn't work."
        case .usernameTaken: "That username is taken. Try another."
        case .invalidUsername: "Usernames are 2 to 24 letters, numbers, dots or underscores."
        case .signupsClosed: "Sundae is invite only right now. Ask the person who invited you."
        case .signInAgain: "That took a while. Sign in with Apple once more to carry on."
        case .sessionExpired: "You've been signed out. Sign in again to carry on."
        }
    }
}
