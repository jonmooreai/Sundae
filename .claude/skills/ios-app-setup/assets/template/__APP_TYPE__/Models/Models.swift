import Foundation

/// The signed-in person, as the server describes them (docs/API.md).
struct User: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var username: String
    var name: String
    var isAdmin: Bool
}

/// The example data. Replace with the app's own models.
struct Note: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var text: String
    let createdAt: Date
}

enum SignInOutcome: Hashable, Sendable {
    /// An account already exists for this Apple Account: everything set up before comes back.
    case signedIn(User)
    /// Nobody has signed in with this Apple Account before. The ticket makes their account, once.
    case newAccount(ticket: String)
}

/// Every failure the app explains to people, in plain words.
enum AppError: LocalizedError, Equatable {
    case offline
    case notAuthorized
    case sessionExpired
    case notFound
    case usernameTaken
    case invalidUsername
    case signupsClosed
    case signInAgain
    case tooMany
    case server

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Try again when you're connected."
        case .notAuthorized, .sessionExpired: "Sign in again to continue."
        case .notFound: "That's no longer here."
        case .usernameTaken: "That username is taken. Try another."
        case .invalidUsername: "Usernames are 2 to 24 letters, numbers, dots or underscores."
        case .signupsClosed: "New accounts aren't open right now."
        case .signInAgain: "Sign in with Apple did not go through. Try again."
        case .tooMany: "You've reached the limit."
        case .server: "Something went wrong. Try again in a moment."
        }
    }
}
