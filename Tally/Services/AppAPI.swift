import Foundation

/// Everything the app asks of its server. `LiveAPI` speaks to the real one (docs/API.md);
/// `MockAPI` is built-in demo data, for building screens and for builds with no server yet.
protocol AppAPI: Sendable {
    // MARK: Session
    /// After Sign in with Apple. `nonce` is the one whose SHA-256 Apple signed into the token.
    func signIn(identityToken: String, nonce: String, fullName: String?) async throws -> SignInOutcome
    /// Spends the ticket from `signIn` on the username someone new chose.
    func createAccount(ticket: String, username: String, name: String?) async throws -> User
    /// The account this phone is signed in to, or nil. Throws only when it can't tell (offline).
    func restoreSession() async throws -> User?
    func signOut() async
    func deleteAccount() async throws

    // MARK: Notes (the example data)
    func notes() async throws -> [Note]
    func addNote(_ text: String) async throws -> Note
    func deleteNote(id: String) async throws
}
