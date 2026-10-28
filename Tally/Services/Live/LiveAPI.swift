import Foundation

/// The real client. Every method is one request against the contract in docs/API.md.
actor LiveAPI: AppAPI {
    private let client: HTTPClient

    init(client: HTTPClient) {
        self.client = client
    }

    // MARK: - Session

    func signIn(identityToken: String, nonce: String, fullName: String?) async throws -> SignInOutcome {
        let response: DTO.AppleSignInResponse = try await client.post(
            "v1/auth/apple",
            body: DTO.AppleSignIn(identityToken: identityToken, nonce: nonce, fullName: fullName, timezone: TimeZone.current.identifier),
            authenticated: false
        )
        if let ticket = response.signupTicket { return .newAccount(ticket: ticket) }
        guard let tokens = response.tokens, let user = response.user else { throw AppError.signInAgain }
        await client.storeTokens(tokens)
        return .signedIn(user)
    }

    func createAccount(ticket: String, username: String, name: String?) async throws -> User {
        let response: DTO.SessionResponse = try await client.post(
            "v1/auth/apple/signup",
            body: DTO.AppleSignUp(signupTicket: ticket, username: username, name: name, timezone: TimeZone.current.identifier),
            authenticated: false
        )
        await client.storeTokens(response.tokens)
        return response.user
    }

    func restoreSession() async throws -> User? {
        guard await client.hasSession else { return nil }
        do {
            let user: User = try await client.get("v1/me")
            return user
        } catch AppError.notAuthorized, AppError.sessionExpired {
            return nil
        }
    }

    func signOut() async {
        do {
            let _: HTTPClient.Empty = try await client.post("v1/auth/signout")
        } catch {
            // Signing out on this phone goes ahead either way; the session runs out on its own.
        }
        await client.clearTokens()
    }

    func deleteAccount() async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/me")
        await client.clearTokens()
    }

    // MARK: - Notes

    func notes() async throws -> [Note] {
        try await client.get("v1/notes")
    }

    func addNote(_ text: String) async throws -> Note {
        try await client.post("v1/notes", body: DTO.NewNote(text: text))
    }

    func deleteNote(id: String) async throws {
        let _: HTTPClient.Empty = try await client.delete("v1/notes/\(id)")
    }
}
