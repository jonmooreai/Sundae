import Foundation

/// Wire types for the Sundae API. Snake-case JSON on the wire (the client converts keys),
/// ISO 8601 timestamps, and `week_start` as a plain `YYYY-MM-DD` date in the user's zone.
/// Each DTO knows how to become the app model it represents.
enum DTO {
    /// `YYYY-MM-DD` in the device's current calendar, matching the server's per-user zone.
    static func weekString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func weekDate(_ string: String) -> Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date.distantPast }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date.distantPast
    }

    struct User: Decodable {
        let id: String
        let username: String
        let name: String?
        let bio: String?
        let avatarUrl: URL?
        let isPublic: Bool
        let timezone: String?

        var model: Sundae.User {
            Sundae.User(id: id, username: username, name: name ?? "", bio: bio ?? "",
                        avatar: avatarUrl.map { .remote($0) }, isPublic: isPublic,
                        timezone: timezone ?? TimeZone.current.identifier)
        }
    }

    struct Tag: Decodable {
        let id: String
        let photoId: String
        let taggerId: String
        let taggedUser: User
        let status: String
        let respondedAt: Date?

        var model: Sundae.Tag {
            Sundae.Tag(id: id, photoID: photoId, taggerID: taggerId, taggedUser: taggedUser.model,
                       status: Sundae.Tag.Status(rawValue: status) ?? .pending, respondedAt: respondedAt)
        }
    }

    struct Photo: Decodable {
        let id: String
        let dumpId: String
        let order: Int
        let url: URL
        let width: Int
        let height: Int
        let altText: String?
        let tags: [Tag]

        var model: Sundae.Photo {
            Sundae.Photo(id: id, dumpID: dumpId, order: order, source: .remote(url), width: width, height: height,
                         altText: altText, tags: tags.map(\.model))
        }
    }

    struct Dump: Decodable {
        let id: String
        let author: User
        let weekStart: String
        let caption: String?
        let createdAt: Date
        let lockedAt: Date?
        let photos: [Photo]
        let commentsEnabled: Bool
        let likedBy: [User]
        let likedByMe: Bool
        let commentCount: Int

        var model: Sundae.Dump {
            Sundae.Dump(id: id, author: author.model, weekStart: DTO.weekDate(weekStart), caption: caption ?? "",
                        createdAt: createdAt, lockedAt: lockedAt, photos: photos.map(\.model).sorted { $0.order < $1.order },
                        commentsEnabled: commentsEnabled, likedBy: likedBy.map(\.model), likedByMe: likedByMe,
                        commentCount: commentCount)
        }
    }

    struct Comment: Decodable {
        let id: String
        let dumpId: String
        let author: User
        let body: String
        let createdAt: Date
        let editedAt: Date?
        let likeCount: Int?
        let likedByMe: Bool?

        var model: Sundae.Comment {
            Sundae.Comment(id: id, dumpID: dumpId, author: author.model, body: body, createdAt: createdAt,
                           editedAt: editedAt, likeCount: likeCount ?? 0, likedByMe: likedByMe ?? false)
        }
    }

    struct TaggedPhoto: Decodable {
        let photo: Photo
        let from: User
        let tag: Tag

        var model: Sundae.TaggedPhoto {
            Sundae.TaggedPhoto(photo: photo.model, from: from.model, tag: tag.model)
        }
    }

    struct ProfileWeek: Decodable {
        let weekStart: String
        let dump: Dump?
        let tagged: [TaggedPhoto]

        var model: Sundae.ProfileWeek {
            Sundae.ProfileWeek(weekStart: DTO.weekDate(weekStart), dump: dump?.model, tagged: tagged.map(\.model))
        }
    }

    struct Profile: Decodable {
        let user: User
        let relationship: String
        let weeks: [ProfileWeek]
        let followerCount: Int?
        let followingCount: Int?

        var model: Sundae.Profile {
            Sundae.Profile(user: user.model, relationship: DTO.relationship(relationship), weeks: weeks.map(\.model),
                           followerCount: followerCount, followingCount: followingCount)
        }
    }

    struct TagRequest: Decodable {
        let tag: Tag
        let photo: Photo
        let tagger: User
        let weekStart: String

        var model: Sundae.TagRequest {
            Sundae.TagRequest(tag: tag.model, photo: photo.model, tagger: tagger.model, weekStart: DTO.weekDate(weekStart))
        }
    }

    struct Relationship: Decodable {
        let relationship: String
    }

    static func relationship(_ raw: String) -> Sundae.Relationship {
        switch raw {
        case "me": .me
        case "following": .following
        case "requested": .requested
        case "blocked": .blocked
        default: .notFollowing
        }
    }

    struct SuggestionDone: Codable {
        let suggestionId: String
        let doneOn: Date

        var model: Sundae.SuggestionDone {
            Sundae.SuggestionDone(suggestionID: suggestionId, doneOn: doneOn)
        }
    }

    struct Settings: Codable {
        var isPublic: Bool
        var autoApproveUserIds: [String]
        var commentsEnabled: Bool
        var hideChallenges: Bool
        var notifySundayReminder: Bool
        var notifyLastCall: Bool
        var notifyTags: Bool
        var notifyFollowRequests: Bool
        var notifyLikesAndComments: Bool
        var notifyTagApproved: Bool

        init(_ s: AccountSettings) {
            isPublic = s.isPublic
            autoApproveUserIds = s.autoApproveUserIDs
            commentsEnabled = s.commentsEnabled
            hideChallenges = s.hideChallenges
            notifySundayReminder = s.notifySundayReminder
            notifyLastCall = s.notifyLastCall
            notifyTags = s.notifyTags
            notifyFollowRequests = s.notifyFollowRequests
            notifyLikesAndComments = s.notifyLikesAndComments
            notifyTagApproved = s.notifyTagApproved
        }

        var model: AccountSettings {
            AccountSettings(isPublic: isPublic, autoApproveUserIDs: autoApproveUserIds, commentsEnabled: commentsEnabled,
                            hideChallenges: hideChallenges, notifySundayReminder: notifySundayReminder,
                            notifyLastCall: notifyLastCall, notifyTags: notifyTags, notifyFollowRequests: notifyFollowRequests,
                            notifyLikesAndComments: notifyLikesAndComments, notifyTagApproved: notifyTagApproved)
        }
    }

    struct ContactsKey: Decodable {
        let keyId: String
        let key: String
        let expiresAt: Date

        var model: ContactsHashingKey? {
            Data(base64Encoded: key).map { ContactsHashingKey(keyID: keyId, key: $0, expiresAt: expiresAt) }
        }
    }

    struct ContactsMatch: Encodable {
        let keyId: String
        let hashes: [String]
    }

    struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
        let user: User

        var tokens: HTTPClient.TokenResponse {
            HTTPClient.TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    // MARK: Requests

    struct AppleSignIn: Encodable {
        let identityToken: String
        let fullName: String?
        let username: String?
        let name: String?
        let timezone: String
    }

    struct PhoneSignIn: Encodable {
        let phone: String
        let code: String
        let username: String?
        let name: String?
        let timezone: String
    }

    struct ProfileUpdate: Encodable {
        let name: String
        let username: String
        let bio: String
    }

    struct AvatarUpdate: Encodable {
        let avatarUploadId: String
    }

    struct UploadRequest: Encodable {
        let contentType: String
        let byteSize: Int
        let width: Int
        let height: Int
    }

    struct UploadTicket: Decodable {
        let uploadId: String
        let url: URL
        let headers: [String: String]?
        let expiresAt: Date
    }

    struct PhotoInput: Encodable {
        /// Existing photo id when the photo is already on the server.
        let id: String?
        /// Upload id from `POST /v1/uploads` for a new photo.
        let uploadId: String?
        let order: Int
        let width: Int
        let height: Int
        let altText: String?
        let taggedUserIds: [String]
    }

    struct SaveDump: Encodable {
        let caption: String
        let commentsEnabled: Bool
        let photos: [PhotoInput]
    }

    struct LikeBody: Encodable {
        let liked: Bool
    }

    struct CommentBody: Encodable {
        let body: String
    }

    struct Respond: Encodable {
        let approve: Bool
    }

    struct Accept: Encodable {
        let accept: Bool
    }

    struct DoneBody: Encodable {
        let doneOn: Date
    }

    struct ReportBody: Encodable {
        let targetType: String
        let targetId: String
        let reason: String
        let note: String?
    }
}
