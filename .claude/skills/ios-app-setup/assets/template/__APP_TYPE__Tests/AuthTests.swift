import Foundation
import Testing
@testable import __APP_TYPE__

/// Sign in with Apple, the account ticket and the stored session, without a server.
struct AuthTests {
    @Test func appleIsGivenTheNoncesSHA256() {
        // The standard SHA-256 test vector, so the server's own hash of the nonce matches.
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func everyNonceIsNewAndURLSafe() {
        let nonces = (0..<50).map { _ in AppleNonce.make() }
        #expect(Set(nonces).count == nonces.count)
        for nonce in nonces {
            // 32 random bytes as base64 without padding.
            #expect(nonce.count == 43)
            #expect(nonce.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        }
    }

    @Test func theSessionIsKeptUntilCleared() throws {
        let store = TokenStore(storage: InMemorySecretStorage())
        #expect(!store.hasSession)
        store.store(accessToken: "access", refreshToken: "refresh", expiresIn: 900)
        #expect(store.hasSession)
        #expect(store.accessToken == "access")
        #expect(store.refreshToken == "refresh")
        let expiry = try #require(store.accessExpiry)
        #expect(expiry.timeIntervalSinceNow > 800)
        store.clear()
        #expect(!store.hasSession)
        #expect(store.accessToken == nil)
        #expect(store.accessExpiry == nil)
    }

    @Test func someoneNewSpendsTheirTicketOnOneAccount() async throws {
        let api = MockAPI()
        let first = try await api.signIn(identityToken: "token", nonce: "nonce-1", fullName: "Pat Doe")
        guard case .newAccount(let ticket) = first else {
            Issue.record("Someone new should get a ticket, not a session")
            return
        }

        // A username that can't be used leaves the ticket for another try.
        await #expect(throws: AppError.invalidUsername) {
            try await api.createAccount(ticket: ticket, username: "p", name: nil)
        }
        let user = try await api.createAccount(ticket: ticket, username: "patdoe", name: "Pat Doe")
        #expect(user.username == "patdoe")

        // Once it has made an account the ticket is spent.
        await #expect(throws: AppError.signInAgain) {
            try await api.createAccount(ticket: ticket, username: "patdoe2", name: nil)
        }

        // Coming back with the same Apple Account signs straight in.
        let again = try await api.signIn(identityToken: "token", nonce: "nonce-2", fullName: nil)
        #expect(again == .signedIn(user))
    }

    @Test func deletingTheAccountTakesEverythingWithIt() async throws {
        let api = MockAPI()
        let first = try await api.signIn(identityToken: "token", nonce: "nonce", fullName: nil)
        guard case .newAccount(let ticket) = first else {
            Issue.record("Someone new should get a ticket")
            return
        }
        _ = try await api.createAccount(ticket: ticket, username: "patdoe", name: nil)
        _ = try await api.addNote("Call Pat at 555-0100")
        let notes = try await api.notes()
        #expect(notes.count == 1)

        try await api.deleteAccount()
        await #expect(throws: AppError.notAuthorized) {
            try await api.notes()
        }
        let afterwards = try await api.signIn(identityToken: "token", nonce: "nonce-2", fullName: nil)
        guard case .newAccount = afterwards else {
            Issue.record("A deleted account should be gone, so signing in starts over")
            return
        }
    }

    @Test func usernamesAreCleanedTheWayTheServerKeepsThem() {
        #expect(UsernameView.clean("Pat.Doe_99!") == "pat.doe_99")
        #expect(UsernameView.clean("zoë doe") == "zodoe")
        #expect(UsernameView.clean(String(repeating: "a", count: 40)).count == 24)
    }
}
