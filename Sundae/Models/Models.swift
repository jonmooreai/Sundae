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

    var displayName: String { name.isEmpty ? username : name }
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
struct DraftPhoto: Identifiable, Hashable, Sendable {
    var id: ID = UUID().uuidString
    var source: PhotoSource
    var width: Int
    var height: Int
    var taggedUsers: [User] = []
    var altText: String = ""
    var takenAt: Date?
}

struct DumpDraft: Hashable, Sendable {
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
}

struct Session: Hashable, Codable, Sendable {
    var token: String
    var user: User
}

enum SignInMethod: Hashable, Sendable {
    case apple(identityToken: String, fullName: String?)
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

    var errorDescription: String? {
        switch self {
        case .sundayClosed: "The feed opens on Sunday."
        case .dumpLocked: "This week's dump is locked. Sunday is over."
        case .tooManyPhotos: "A dump holds up to \(DumpDraft.maxPhotos) photos."
        case .tooManyTags: "You can tag up to \(DumpDraft.maxTagsPerPhoto) people per photo."
        case .captionTooLong: "Captions are up to \(DumpDraft.maxCaptionLength) characters."
        case .notAuthorized: "You can't do that."
        case .notFound: "That's gone."
        case .offline: "You're offline. We'll keep your draft."
        case .invalidCode: "That code didn't work."
        }
    }
}
