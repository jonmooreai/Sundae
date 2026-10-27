import Foundation

/// The real client. Every method is one or two requests against the contract in `docs/API.md`.
/// Photos are uploaded to single-use pre-signed URLs before the dump is saved, and the dump
/// save references them by upload id, so a retry after a dropped connection never re-uploads.
actor LiveSundaeAPI: SundaeAPI {
    private let client: HTTPClient
    private let uploader: BackgroundUploader
    /// Draft photo id to upload id, so an interrupted save can resume without re-uploading.
    private var uploads: [ID: String] = [:]

    init(client: HTTPClient, uploader: BackgroundUploader = .shared) {
        self.client = client
        self.uploader = uploader
    }

    // MARK: - Session

    func signIn(_ method: SignInMethod) async throws -> SignInOutcome {
        // The server signs people in with Apple only (docs/SERVER.md).
        guard case .apple(let identityToken, let fullName, let nonce) = method else { throw SundaeError.notAuthorized }
        let response: DTO.AppleSignInResponse = try await client.post(
            "v1/auth/apple",
            body: DTO.AppleSignIn(identityToken: identityToken, nonce: nonce, fullName: fullName, timezone: TimeZone.current.identifier),
            authenticated: false
        )
        if let ticket = response.signupTicket { return .newAccount(ticket: ticket) }
        guard let tokens = response.tokens, let user = response.user else { throw SundaeError.signInAgain }
        await client.storeTokens(tokens)
        return .signedIn(Session(token: "live", user: user.model))
    }

    func createAccount(ticket: String, username: String, name: String?) async throws -> Session {
        let response: DTO.SessionResponse = try await client.post(
            "v1/auth/apple/signup",
            body: DTO.AppleSignUp(signupTicket: ticket, username: username, name: name, timezone: TimeZone.current.identifier),
            authenticated: false
        )
        await client.storeTokens(response.tokens)
        return Session(token: "live", user: response.user.model)
    }

    func restoreSession(token: String) async throws -> User? {
        guard await client.hasSession else { return nil }
        do {
            let user: DTO.User = try await client.get("v1/me")
            return user.model
        } catch SundaeError.notAuthorized, SundaeError.sessionExpired {
            return nil
        }
    }

    func signOut() async throws {
        do {
            let _: HTTPClient.Empty = try await client.post("v1/auth/signout")
        } catch {
            // Local sign-out proceeds either way; the refresh token expires on its own.
        }
        await client.clearTokens()
    }

    func signOutEverywhere() async throws {
        // Unlike a plain sign-out, this one has to reach the server to mean anything.
        let _: HTTPClient.Empty = try await client.post("v1/auth/signout", body: DTO.SignOut(everywhere: true))
        await client.clearTokens()
    }

    func updateProfile(name: String, username: String, bio: String) async throws -> User {
        let user: DTO.User = try await client.patch("v1/me", body: DTO.ProfileUpdate(name: name, username: username, bio: bio))
        return user.model
    }

    func updateAvatar(_ photo: ProcessedPhoto) async throws -> User {
        let ticket: DTO.UploadTicket = try await client.post(
            "v1/uploads",
            body: DTO.UploadRequest(contentType: "image/jpeg", byteSize: photo.data.count, width: photo.width, height: photo.height)
        )
        try await uploader.upload(photo.data, to: ticket.url, headers: ticket.headers ?? [:], contentType: "image/jpeg")
        let user: DTO.User = try await client.patch("v1/me", body: DTO.AvatarUpdate(avatarUploadId: ticket.uploadId))
        return user.model
    }

    func accountSettings() async throws -> AccountSettings {
        let settings: DTO.Settings = try await client.get("v1/me/settings")
        return settings.model
    }

    func updateAccountSettings(_ patch: AccountSettingsPatch) async throws {
        // Only what changed: the server merges it, so a stale copy can't undo a newer change.
        let _: HTTPClient.Empty = try await client.put("v1/me/settings", body: DTO.SettingsPatch(patch))
    }

    func deleteAccount() async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/me")
        await client.clearTokens()
    }

    // MARK: - Feed and dumps

    func feed(olderThan: Date?, limit: Int) async throws -> [Dump] {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let olderThan {
            query.append(URLQueryItem(name: "before", value: Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(olderThan)))
        }
        // One dump that can't be read is left out rather than failing the whole page.
        let dumps: DTO.LossyList<DTO.Dump> = try await client.get("v1/feed", query: query)
        return dumps.elements.map(\.model)
    }

    func dump(id: ID) async throws -> Dump {
        let dump: DTO.Dump = try await client.get("v1/dumps/\(id)")
        return dump.model
    }

    func myDump(weekStart: Date) async throws -> Dump? {
        do {
            let dump: DTO.Dump = try await client.get("v1/me/dumps/\(DTO.weekString(weekStart))")
            return dump.model
        } catch SundaeError.notFound {
            return nil
        }
    }

    func saveDump(_ draft: DumpDraft, weekStart: Date) async throws -> Dump {
        var inputs: [DTO.PhotoInput] = []
        for (order, photo) in draft.photos.enumerated() {
            let tagged = photo.taggedUsers.map(\.id)
            let alt = photo.altText.isEmpty ? nil : photo.altText
            switch photo.source {
            case .remote:
                inputs.append(DTO.PhotoInput(id: photo.id, uploadId: nil, order: order, width: photo.width,
                                             height: photo.height, altText: alt, caption: photo.caption, taggedUserIds: tagged))
            case .data(let data):
                let uploadID = try await upload(data, for: photo)
                inputs.append(DTO.PhotoInput(id: nil, uploadId: uploadID, order: order, width: photo.width,
                                             height: photo.height, altText: alt, caption: photo.caption, taggedUserIds: tagged))
            case .placeholder:
                continue
            }
        }
        let body = DTO.SaveDump(caption: draft.caption, commentsEnabled: draft.commentsEnabled, photos: inputs)
        let saved: DTO.Dump = try await client.put("v1/me/dumps/\(DTO.weekString(weekStart))", body: body)
        uploads = [:]
        return saved.model
    }

    private func upload(_ data: Data, for photo: DraftPhoto) async throws -> String {
        if let existing = uploads[photo.id] { return existing }
        let ticket: DTO.UploadTicket = try await client.post(
            "v1/uploads",
            body: DTO.UploadRequest(contentType: "image/jpeg", byteSize: data.count, width: photo.width, height: photo.height)
        )
        try await uploader.upload(data, to: ticket.url, headers: ticket.headers ?? [:], contentType: "image/jpeg")
        uploads[photo.id] = ticket.uploadId
        return ticket.uploadId
    }

    func deleteDump(id: ID) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/dumps/\(id)")
    }

    func setLike(dumpID: ID, liked: Bool) async throws -> Dump {
        let dump: DTO.Dump = try await client.put("v1/dumps/\(dumpID)/like", body: DTO.LikeBody(liked: liked))
        return dump.model
    }

    func setCherry(photoID: ID, cherried: Bool) async throws -> Photo {
        let photo: DTO.Photo = try await client.put("v1/photos/\(photoID)/cherry", body: DTO.CherryBody(cherried: cherried))
        return photo.model
    }

    func comments(dumpID: ID) async throws -> [Comment] {
        let comments: [DTO.Comment] = try await client.get("v1/dumps/\(dumpID)/comments")
        return comments.map(\.model)
    }

    func updateComment(id: ID, body: String) async throws -> Comment {
        let comment: DTO.Comment = try await client.patch("v1/comments/\(id)", body: DTO.CommentBody(body: body))
        return comment.model
    }

    func deleteComment(id: ID) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/comments/\(id)")
    }

    func setCommentLike(id: ID, liked: Bool) async throws -> Comment {
        let comment: DTO.Comment
        if liked {
            comment = try await client.put("v1/comments/\(id)/like")
        } else {
            comment = try await client.delete("v1/comments/\(id)/like")
        }
        return comment.model
    }

    func addComment(dumpID: ID, body: String, replyingTo parentID: ID?) async throws -> Comment {
        let comment: DTO.Comment = try await client.post("v1/dumps/\(dumpID)/comments", body: DTO.CommentBody(body: body, parentId: parentID))
        return comment.model
    }

    // MARK: - People

    func profile(userID: ID) async throws -> Profile {
        let profile: DTO.Profile = try await client.get("v1/users/\(userID)/profile")
        return profile.model
    }

    func searchUsers(_ query: String) async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/users/search", query: [URLQueryItem(name: "q", value: query)])
        return users.map(\.model)
    }

    func suggestedUsers() async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/users/suggested")
        return users.map(\.model)
    }

    func follow(userID: ID) async throws -> Relationship {
        let response: DTO.Relationship = try await client.post("v1/users/\(userID)/follow")
        return DTO.relationship(response.relationship)
    }

    func unfollow(userID: ID) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/users/\(userID)/follow")
    }

    func followRequests() async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/me/follow-requests")
        return users.map(\.model)
    }

    func respondToFollowRequest(from userID: ID, accept: Bool) async throws {
        let _: HTTPClient.Empty = try await client.post("v1/me/follow-requests/\(userID)", body: DTO.Accept(accept: accept))
    }

    func taggableUsers() async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/me/taggable")
        return users.map(\.model)
    }

    func followers() async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/me/followers")
        return users.map(\.model)
    }

    func following() async throws -> [User] {
        let users: [DTO.User] = try await client.get("v1/me/following")
        return users.map(\.model)
    }

    func followList(of userID: ID, _ list: PeopleList) async throws -> [ListedPerson] {
        let people: [DTO.ListedUser] = try await client.get("v1/users/\(userID)/\(list == .followers ? "followers" : "following")")
        return people.map(\.model)
    }

    func removeFollower(userID: ID) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/me/followers/\(userID)")
    }


    // MARK: - Tags

    func pendingTagRequests() async throws -> [TagRequest] {
        let requests: DTO.LossyList<DTO.TagRequest> = try await client.get("v1/me/tag-requests")
        return requests.elements.map(\.model)
    }

    func respondToTag(id: ID, approve: Bool) async throws {
        let _: HTTPClient.Empty = try await client.post("v1/tags/\(id)/respond", body: DTO.Respond(approve: approve))
    }

    func removeTaggedPhoto(tagID: ID) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/tags/\(tagID)")
    }

    // MARK: - Suggestions, safety

    func suggestionsDone(weekStart: Date) async throws -> [SuggestionDone] {
        let done: [DTO.SuggestionDone] = try await client.get(
            "v1/me/suggestions/done", query: [URLQueryItem(name: "week_start", value: DTO.weekString(weekStart))]
        )
        return done.map(\.model)
    }

    func markSuggestionDone(id: String, on day: Date) async throws {
        let _: HTTPClient.Empty = try await client.put("v1/me/suggestions/\(id)/done", body: DTO.DoneBody(doneOn: day))
    }

    // MARK: - Ideas near you (weekdays, anonymous)

    /// No bearer token, by design: the server sees a cell and a day, never who asked.
    func localIdeas(cell: String, day: Date) async throws -> [Suggestion] {
        let ideas: [DTO.LocalIdea] = try await client.get(
            "v1/ideas/local",
            query: [URLQueryItem(name: "cell", value: cell), URLQueryItem(name: "day", value: DTO.weekString(day))],
            authenticated: false
        )
        return ideas.map(\.model)
    }

    func block(userID: ID) async throws {
        let _: HTTPClient.Empty = try await client.post("v1/users/\(userID)/block")
    }

    func report(_ report: Report) async throws {
        let body = DTO.ReportBody(targetType: report.target.rawValue, targetId: report.targetID,
                                  reason: report.reason.rawValue, note: report.note.isEmpty ? nil : report.note)
        let _: HTTPClient.Empty = try await client.post("v1/reports", body: body)
    }
}
