import Foundation

/// Built-in demo data, in memory, for builds with no server address and for tests. Behaves like
/// the server where it matters: a ticket makes one account, usernames are unique, deleting an
/// account takes its notes. The demo account is an admin, so every screen can be seen.
actor MockAPI: AppAPI {
    private static let demoAppleID = "demo-apple-id"

    private var accounts: [String: User] = [:]
    private var tickets: [String: String] = [:]
    private var current: (appleID: String, user: User)?
    private var notesByUser: [String: [Note]] = [:]

    init() {}

    func signIn(identityToken: String, nonce: String, fullName: String?) async throws -> SignInOutcome {
        let appleID = Self.demoAppleID
        if let user = accounts[appleID] {
            current = (appleID, user)
            return .signedIn(user)
        }
        let ticket = "ticket-\(UUID().uuidString)"
        tickets[ticket] = appleID
        return .newAccount(ticket: ticket)
    }

    func createAccount(ticket: String, username: String, name: String?) async throws -> User {
        // Like the server: a ticket is spent only when it makes the account, so a taken or
        // invalid username can be tried again with the same one.
        guard let appleID = tickets[ticket], accounts[appleID] == nil else { throw AppError.signInAgain }
        guard username.count >= 2 else { throw AppError.invalidUsername }
        guard !accounts.values.contains(where: { $0.username == username }) else { throw AppError.usernameTaken }
        tickets[ticket] = nil
        let user = User(id: "u_\(UUID().uuidString.prefix(12).lowercased())", username: username, name: name ?? "", isAdmin: true)
        accounts[appleID] = user
        current = (appleID, user)
        return user
    }

    func restoreSession() async throws -> User? {
        current?.user
    }

    func signOut() async {
        current = nil
    }

    func deleteAccount() async throws {
        guard let current else { throw AppError.notAuthorized }
        accounts[current.appleID] = nil
        notesByUser[current.user.id] = nil
        self.current = nil
    }

    func notes() async throws -> [Note] {
        guard let current else { throw AppError.notAuthorized }
        return notesByUser[current.user.id] ?? []
    }

    func addNote(_ text: String) async throws -> Note {
        guard let current else { throw AppError.notAuthorized }
        let note = Note(id: "n_\(UUID().uuidString.prefix(12).lowercased())", text: text, createdAt: Date())
        notesByUser[current.user.id, default: []].insert(note, at: 0)
        return note
    }

    func deleteNote(id: String) async throws {
        guard let current else { throw AppError.notAuthorized }
        guard notesByUser[current.user.id]?.contains(where: { $0.id == id }) == true else { throw AppError.notFound }
        notesByUser[current.user.id]?.removeAll { $0.id == id }
    }
}
