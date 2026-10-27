import Foundation

/// The contract between the app and the Sundae backend.
///
/// Every rule in the PRD (the Sunday gate, one dump per week, the edit lock, the 15-photo cap,
/// who can tag whom) is enforced on the server. The client only decides what to draw.
/// `MockSundaeAPI` mirrors those rules so the app behaves honestly before the backend exists.
protocol SundaeAPI: Sendable {
    // MARK: Session (every day)
    /// Someone coming back is signed in. Someone new gets a ticket instead, and no account exists
    /// until `createAccount` spends it on the username they choose.
    func signIn(_ method: SignInMethod) async throws -> SignInOutcome
    func createAccount(ticket: String, username: String, name: String?) async throws -> Session
    func restoreSession(token: String) async throws -> User?
    func signOut() async throws
    /// Signs out every device signed in to this account, this one included.
    func signOutEverywhere() async throws
    func updateProfile(name: String, username: String, bio: String) async throws -> User
    /// Replaces the profile photo with an already re-encoded image.
    func updateAvatar(_ photo: ProcessedPhoto) async throws -> User
    func accountSettings() async throws -> AccountSettings
    /// Changes only the fields in the patch. The server keeps every other one as it is.
    func updateAccountSettings(_ patch: AccountSettingsPatch) async throws
    func deleteAccount() async throws

    // MARK: Sunday only
    func feed(olderThan: Date?, limit: Int) async throws -> [Dump]
    func dump(id: ID) async throws -> Dump
    func myDump(weekStart: Date) async throws -> Dump?
    func saveDump(_ draft: DumpDraft, weekStart: Date) async throws -> Dump
    func deleteDump(id: ID) async throws
    func setLike(dumpID: ID, liked: Bool) async throws -> Dump
    func comments(dumpID: ID) async throws -> [Comment]
    func addComment(dumpID: ID, body: String) async throws -> Comment
    /// Only the author may edit. Returns the comment with `editedAt` set.
    func updateComment(id: ID, body: String) async throws -> Comment
    /// The author or the dump's author may delete.
    func deleteComment(id: ID) async throws
    func setCommentLike(id: ID, liked: Bool) async throws -> Comment
    func profile(userID: ID) async throws -> Profile
    func searchUsers(_ query: String) async throws -> [User]
    func suggestedUsers() async throws -> [User]
    func follow(userID: ID) async throws -> Relationship
    func unfollow(userID: ID) async throws
    func followRequests() async throws -> [User]
    func respondToFollowRequest(from userID: ID, accept: Bool) async throws
    /// People the user follows or who follow them. The only people they can tag.
    func taggableUsers() async throws -> [User]

    // MARK: Weekdays only, anonymous
    /// Ideas for a neighborhood-sized geohash cell on a given day. Sent without a bearer token on
    /// purpose: the server cannot tie an area to an account, and every phone in the cell shares one
    /// cached answer. The server answers `sunday_closed` when `day` is a Sunday.
    func localIdeas(cell: String, day: Date) async throws -> [Suggestion]

    // MARK: Every day
    /// People whose follow of the user is accepted, by username.
    func followers() async throws -> [User]
    /// People the user follows, accepted, by username.
    func following() async throws -> [User]
    /// Someone's followers or the people they follow, for whoever can see their profile. Sunday
    /// only, like profiles.
    func followList(of userID: ID, _ list: PeopleList) async throws -> [ListedPerson]
    /// Ends that person's follow of the user, or their request. Following again is a new request
    /// while the account is private.
    func removeFollower(userID: ID) async throws
    func pendingTagRequests() async throws -> [TagRequest]
    func respondToTag(id: ID, approve: Bool) async throws
    func removeTaggedPhoto(tagID: ID) async throws
    func suggestionsDone(weekStart: Date) async throws -> [SuggestionDone]
    func markSuggestionDone(id: String, on day: Date) async throws
    func block(userID: ID) async throws
    func report(_ report: Report) async throws
}

extension SundaeAPI {
    /// Demo data has one device, so everywhere is here.
    func signOutEverywhere() async throws {
        try await signOut()
    }
}
