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
        let birthday: String?
        let invitedByMe: Bool?
        let isAdmin: Bool?

        var model: Sundae.User {
            Sundae.User(id: id, username: username, name: name ?? "", bio: bio ?? "",
                        avatar: avatarUrl.map { .remote($0) }, isPublic: isPublic,
                        timezone: timezone ?? TimeZone.current.identifier, birthday: birthday, invitedByMe: invitedByMe,
                        isAdmin: isAdmin)
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
        let caption: String?
        let tags: [Tag]
        let cherryCount: Int
        let cherriedByMe: Bool
        let cherriedBy: [User]

        private enum CodingKeys: String, CodingKey {
            case id, dumpId, order, url, width, height, altText, caption, tags, cherryCount, cherriedByMe, cherriedBy
        }

        var model: Sundae.Photo {
            Sundae.Photo(id: id, dumpID: dumpId, order: order, source: .remote(url), width: width, height: height,
                         altText: altText, caption: caption, tags: tags.map(\.model),
                         cherryCount: cherryCount, cherriedByMe: cherriedByMe, cherriedBy: cherriedBy.map(\.model))
        }

        /// Width and height only shape the frame, so an odd value (a fraction, a huge number,
        /// null) becomes a sane one instead of failing the whole response.
        static func dimension(_ value: Double?) -> Int {
            guard let value, value.isFinite, value >= 1 else { return 1 }
            return Int(min(value, Double(maxDimension)).rounded())
        }

        static let maxDimension = 20_000
    }

    /// A list that skips any element it cannot read, so one bad record never empties a screen.
    struct LossyList<Element: Decodable>: Decodable {
        let elements: [Element]

        /// Always decodes, so a skipped element still moves the list along.
        private struct Skip: Decodable {
            init(from decoder: any Decoder) {}
        }

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var elements: [Element] = []
            while !container.isAtEnd {
                if let element = try? container.decode(Element.self) {
                    elements.append(element)
                } else {
                    _ = try container.decode(Skip.self)
                }
            }
            self.elements = elements
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
        let isAuthorsFirst: Bool?

        var model: Sundae.Dump {
            Sundae.Dump(id: id, author: author.model, weekStart: DTO.weekDate(weekStart), caption: caption ?? "",
                        createdAt: createdAt, lockedAt: lockedAt, photos: photos.map(\.model).sorted { $0.order < $1.order },
                        commentsEnabled: commentsEnabled, likedBy: likedBy.map(\.model), likedByMe: likedByMe,
                        commentCount: commentCount, isAuthorsFirst: isAuthorsFirst)
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
        let parentId: String?

        var model: Sundae.Comment {
            Sundae.Comment(id: id, dumpID: dumpId, author: author.model, body: body, createdAt: createdAt,
                           editedAt: editedAt, likeCount: likeCount ?? 0, likedByMe: likedByMe ?? false, parentID: parentId)
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
        let tagged: LossyList<TaggedPhoto>

        var model: Sundae.ProfileWeek {
            Sundae.ProfileWeek(weekStart: DTO.weekDate(weekStart), dump: dump?.model, tagged: tagged.elements.map(\.model))
        }
    }

    struct Profile: Decodable {
        let user: User
        let relationship: String
        let weeks: LossyList<ProfileWeek>
        let followerCount: Int?
        let followingCount: Int?

        var model: Sundae.Profile {
            Sundae.Profile(user: user.model, relationship: DTO.relationship(relationship), weeks: weeks.elements.map(\.model),
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

    /// A user, with how the caller stands with them, in a followers or following list.
    struct ListedUser: Decodable {
        let user: User
        let relationship: String
        let followsYou: Bool

        private enum CodingKeys: String, CodingKey {
            case relationship, followsYou
        }

        init(from decoder: any Decoder) throws {
            user = try User(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            relationship = (try? container.decodeIfPresent(String.self, forKey: .relationship)) ?? "none"
            followsYou = (try? container.decodeIfPresent(Bool.self, forKey: .followsYou)) ?? false
        }

        var model: Sundae.ListedPerson {
            Sundae.ListedPerson(user: user.model, relationship: DTO.relationship(relationship), followsYou: followsYou)
        }
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

    /// One idea near the caller's area. `id` is `local:<day>:<n>` and never names the area.
    struct LocalIdea: Decodable {
        struct Place: Decodable {
            let name: String
            let walkMinutes: Int?
            let distanceMeters: Double?
            let latitude: Double?
            let longitude: Double?
        }

        let id: String
        let text: String
        let reason: String
        let timeOfDay: String
        let place: Place?

        var model: Suggestion {
            Suggestion(id: id.hasPrefix(Suggestion.nearbyPrefix) ? id : Suggestion.nearbyPrefix + id,
                       text: text, reason: reason, categories: [.local],
                       timeOfDay: Suggestion.TimeOfDay(rawValue: timeOfDay) ?? .any,
                       place: place.map { Suggestion.Place(name: $0.name, walkMinutes: $0.walkMinutes,
                                                           distanceMeters: $0.distanceMeters,
                                                           latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    /// The whole settings object, as `GET me/settings` sends it. Saving sends `SettingsPatch`.
    struct Settings: Decodable {
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

        var model: AccountSettings {
            AccountSettings(isPublic: isPublic, autoApproveUserIDs: autoApproveUserIds, commentsEnabled: commentsEnabled,
                            hideChallenges: hideChallenges, notifySundayReminder: notifySundayReminder,
                            notifyLastCall: notifyLastCall, notifyTags: notifyTags, notifyFollowRequests: notifyFollowRequests,
                            notifyLikesAndComments: notifyLikesAndComments, notifyTagApproved: notifyTagApproved)
        }
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

    /// Only the settings that changed. A nil field is left out of the JSON, and the server
    /// keeps what it has for it.
    struct SettingsPatch: Encodable {
        var isPublic: Bool?
        var autoApproveUserIds: [String]?
        var commentsEnabled: Bool?
        var hideChallenges: Bool?
        var notifySundayReminder: Bool?
        var notifyLastCall: Bool?
        var notifyTags: Bool?
        var notifyFollowRequests: Bool?
        var notifyLikesAndComments: Bool?
        var notifyTagApproved: Bool?

        init(_ p: AccountSettingsPatch) {
            isPublic = p.isPublic
            autoApproveUserIds = p.autoApproveUserIDs
            commentsEnabled = p.commentsEnabled
            hideChallenges = p.hideChallenges
            notifySundayReminder = p.notifySundayReminder
            notifyLastCall = p.notifyLastCall
            notifyTags = p.notifyTags
            notifyFollowRequests = p.notifyFollowRequests
            notifyLikesAndComments = p.notifyLikesAndComments
            notifyTagApproved = p.notifyTagApproved
        }
    }

    struct SignOut: Encodable {
        let everywhere: Bool
    }

    struct AppleSignIn: Encodable {
        let identityToken: String
        let nonce: String
        let fullName: String?
        let timezone: String
        /// Asks for a sign-up ticket, not an account, when this Apple ID is new.
        var profileFirst = true
    }

    /// A session for someone coming back, or a ticket for someone new.
    struct AppleSignInResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: TimeInterval?
        let user: User?
        let signupTicket: String?

        var tokens: HTTPClient.TokenResponse? {
            guard let accessToken, let refreshToken, let expiresIn else { return nil }
            return HTTPClient.TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    struct AppleSignUp: Encodable {
        let signupTicket: String
        let username: String
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
        /// Always sent, empty for none, so clearing a caption clears it on the server.
        let caption: String
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
        /// Present for a reply.
        var parentId: String? = nil
    }

    struct CherryBody: Encodable {
        let cherried: Bool
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

extension DTO.Photo {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dumpId = try container.decode(String.self, forKey: .dumpId)
        order = try container.decode(Int.self, forKey: .order)
        url = try container.decode(URL.self, forKey: .url)
        width = Self.dimension(try? container.decodeIfPresent(Double.self, forKey: .width))
        height = Self.dimension(try? container.decodeIfPresent(Double.self, forKey: .height))
        altText = try container.decodeIfPresent(String.self, forKey: .altText)
        caption = try? container.decodeIfPresent(String.self, forKey: .caption)
        tags = try container.decode([DTO.Tag].self, forKey: .tags)
        // A server from before cherries sends none; that is no cherries, not a broken photo.
        cherryCount = max(0, (try? container.decodeIfPresent(Int.self, forKey: .cherryCount)) ?? 0)
        cherriedByMe = (try? container.decodeIfPresent(Bool.self, forKey: .cherriedByMe)) ?? false
        cherriedBy = (try? container.decodeIfPresent(DTO.LossyList<DTO.User>.self, forKey: .cherriedBy))?.elements ?? []
    }
}

/// Generic structs are not Sendable by inference; the list is plain data whenever its elements are.
extension DTO.LossyList: Sendable where Element: Sendable {}
