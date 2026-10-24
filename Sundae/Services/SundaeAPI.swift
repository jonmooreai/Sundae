import Foundation

/// The contract between the app and the Sundae backend.
///
/// Every rule in the PRD (the Sunday gate, one dump per week, the edit lock, the 15-photo cap,
/// who can tag whom) is enforced on the server. The client only decides what to draw.
/// `MockSundaeAPI` mirrors those rules so the app behaves honestly before the backend exists.
protocol SundaeAPI: Sendable {
    // MARK: Session (every day)
    func signIn(_ method: SignInMethod, username: String?, name: String?) async throws -> Session
    func restoreSession(token: String) async throws -> User?
    func signOut() async throws
    func updateProfile(name: String, username: String, bio: String) async throws -> User
    func accountSettings() async throws -> AccountSettings
    func updateAccountSettings(_ settings: AccountSettings) async throws
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
    func profile(userID: ID) async throws -> Profile
    func searchUsers(_ query: String) async throws -> [User]
    func suggestedUsers() async throws -> [User]
    func follow(userID: ID) async throws -> Relationship
    func unfollow(userID: ID) async throws
    func followRequests() async throws -> [User]
    func respondToFollowRequest(from userID: ID, accept: Bool) async throws
    /// People the user follows or who follow them. The only people they can tag.
    func taggableUsers() async throws -> [User]

    // MARK: Every day
    func pendingTagRequests() async throws -> [TagRequest]
    func respondToTag(id: ID, approve: Bool) async throws
    func removeTaggedPhoto(tagID: ID) async throws
    func suggestionsDone(weekStart: Date) async throws -> [SuggestionDone]
    func markSuggestionDone(id: String, on day: Date) async throws
    func block(userID: ID) async throws
    func report(_ report: Report) async throws
}
