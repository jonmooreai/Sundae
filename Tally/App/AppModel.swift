import Observation
import SwiftUI
import UIKit

/// The app's state: who is signed in, and their data. One instance, made by the App and handed to
/// every screen through the environment. Talks to the server through `AppAPI`: the live client
/// when a server address is configured, built-in demo data otherwise.
@MainActor
@Observable
final class AppModel {
    let api: any AppAPI
    /// True with no server configured: the app runs on demo data, and sign-in offers a demo.
    let isUsingMock: Bool

    private(set) var currentUser: User?
    private(set) var isRestoringSession = true
    /// Set when Sign in with Apple found no account: the username step spends it.
    private(set) var signupTicket: String?
    /// The name Apple shared on a first sign-in, to fill in the username step.
    private(set) var signupName: String?
    private(set) var notes: [Note] = []
    private(set) var loadFailed = false

    private let sessionEnded: AsyncStream<Void>
    private var sessionWatch: Task<Void, Never>?

    private static let cachedUserKey = "session.user"

    var isSignedIn: Bool { currentUser != nil }
    var isAdmin: Bool { currentUser?.isAdmin == true }

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        sessionEnded = stream
        if let baseURL = APIConfiguration.baseURL {
            api = LiveAPI(client: HTTPClient(baseURL: baseURL, onSessionExpired: continuation))
            isUsingMock = false
        } else {
            api = MockAPI()
            isUsingMock = true
        }
    }

    // MARK: - Lifecycle

    func start() async {
        // Before the Keychain is read, so a phone's previous owner is never signed back in.
        clearSessionLeftByAnEarlierInstall()
        watchForEndedSession()
        do {
            currentUser = try await api.restoreSession()
        } catch {
            // Offline at launch: trust the account this phone last had until the server answers.
            currentUser = cachedUser()
        }
        cache(currentUser)
        isRestoringSession = false
        if isSignedIn { await loadNotes() }
    }

    func becameActive() async {
        guard !isRestoringSession, isSignedIn else { return }
        await loadNotes()
    }

    // MARK: - Signing in

    /// After Sign in with Apple. Someone coming back is in; someone new goes on to a username.
    func signInWithApple(identityToken: String, nonce: String, fullName: String?) async throws {
        switch try await api.signIn(identityToken: identityToken, nonce: nonce, fullName: fullName) {
        case .signedIn(let user):
            await didSignIn(user)
        case .newAccount(let ticket):
            signupName = fullName
            signupTicket = ticket
        }
    }

    func createAccount(username: String, name: String?) async throws {
        guard let ticket = signupTicket else { throw AppError.signInAgain }
        do {
            let user = try await api.createAccount(ticket: ticket, username: username, name: name)
            signupTicket = nil
            signupName = nil
            await didSignIn(user)
        } catch AppError.signInAgain, AppError.notAuthorized {
            // The ticket ran out, or already made an account. Apple once more sorts out both.
            signupTicket = nil
            throw AppError.signInAgain
        }
    }

    func cancelSignUp() {
        signupTicket = nil
        signupName = nil
    }

    func signOut() async {
        await api.signOut()
        endSession()
    }

    func deleteAccount() async throws {
        try await api.deleteAccount()
        endSession()
    }

    private func didSignIn(_ user: User) async {
        currentUser = user
        cache(user)
        await loadNotes()
    }

    private func endSession() {
        currentUser = nil
        notes = []
        cache(nil)
    }

    /// The server refused to renew the session (revoked, expired, or used on another device).
    private func watchForEndedSession() {
        guard sessionWatch == nil else { return }
        let stream = sessionEnded
        sessionWatch = Task { [weak self] in
            for await _ in stream {
                self?.endSession()
            }
        }
    }

    /// The Keychain outlives a deleted app. On a fresh install, tokens found there belong to
    /// whoever used this phone before, so they are cleared and never sent.
    private func clearSessionLeftByAnEarlierInstall() {
        // Before first unlock UserDefaults can read as empty; check on a later launch instead.
        guard UIApplication.shared.isProtectedDataAvailable else { return }
        guard FreshInstall.check(.standard, evidence: [Self.cachedUserKey]) else { return }
        TokenStore().clear()
    }

    private func cache(_ user: User?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
        }
    }

    private func cachedUser() -> User? {
        UserDefaults.standard.data(forKey: Self.cachedUserKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }

    // MARK: - Notes (the example data)

    func loadNotes() async {
        do {
            notes = try await api.notes()
            loadFailed = false
        } catch {
            loadFailed = notes.isEmpty
        }
    }

    func addNote(_ text: String) async throws {
        let note = try await api.addNote(text)
        notes.insert(note, at: 0)
    }

    func deleteNotes(_ ids: [String]) async {
        for id in ids {
            do {
                try await api.deleteNote(id: id)
                notes.removeAll { $0.id == id }
            } catch {
                // Left in the list, so it can be tried again.
            }
        }
    }
}
