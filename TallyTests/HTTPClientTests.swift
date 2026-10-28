import Foundation
import Synchronization
import Testing
@testable import Tally

/// Answers every request from a handler so the HTTP client can be exercised without a server.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)

    static let handler = Mutex<Handler?>(nil)
    static let requests = Mutex<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        guard let handler = Self.handler.withLock({ $0 }), let url = request.url else { return }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(_ handler: Handler?) {
        Self.handler.withLock { $0 = handler }
        Self.requests.withLock { $0 = [] }
    }
}

/// The client against a stub server: error codes, the token refresh, and the session ending.
@Suite(.serialized)
struct HTTPClientTests {
    private func makeClient(onSessionExpired: AsyncStream<Void>.Continuation? = nil) -> (HTTPClient, TokenStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let tokens = TokenStore(storage: InMemorySecretStorage())
        tokens.store(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 3600)
        let client = HTTPClient(baseURL: URL(string: "https://api.example.test")!, tokens: tokens,
                                session: URLSession(configuration: configuration), onSessionExpired: onSessionExpired)
        return (client, tokens)
    }

    /// How many times the client said the session ended, once it can't say so again.
    private func timesTold(_ ended: AsyncStream<Void>, _ onEnded: AsyncStream<Void>.Continuation) async -> Int {
        onEnded.finish()
        var count = 0
        for await _ in ended { count += 1 }
        return count
    }

    @Test func serverErrorCodesBecomeAppErrors() async throws {
        StubURLProtocol.reset { _ in
            (409, Data(#"{"error":{"code":"username_taken","message":"That username is taken."}}"#.utf8))
        }
        let (client, _) = makeClient()
        await #expect(throws: AppError.usernameTaken) {
            let _: User = try await client.get("v1/me")
        }
    }

    @Test func keysAreSnakeCaseOnTheWire() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"id":"u_1","username":"patdoe","name":"Pat Doe","is_admin":true}"#.utf8))
        }
        let (client, _) = makeClient()
        let user: User = try await client.get("v1/me")
        #expect(user.isAdmin)
        #expect(user.username == "patdoe")
    }

    @Test func aRejectedAccessTokenIsRefreshedOnceAndRetried() async throws {
        StubURLProtocol.reset { request in
            let path = request.url?.path() ?? ""
            let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
            if path.hasSuffix("auth/refresh") {
                return (200, Data(#"{"access_token":"access-2","refresh_token":"refresh-2","expires_in":900}"#.utf8))
            }
            if auth == "Bearer access-1" {
                return (401, Data(#"{"error":{"code":"unauthorized"}}"#.utf8))
            }
            return (200, Data("[]".utf8))
        }
        let (client, tokens) = makeClient()
        let notes: [Note] = try await client.get("v1/notes")
        #expect(notes.isEmpty)

        let paths = StubURLProtocol.requests.withLock { $0.map { $0.url?.path() ?? "" } }
        #expect(paths.filter { $0.hasSuffix("auth/refresh") }.count == 1)
        #expect(paths.filter { $0.hasSuffix("v1/notes") }.count == 2)
        #expect(tokens.accessToken == "access-2")
        #expect(tokens.refreshToken == "refresh-2")
    }

    @Test func aRejectedRefreshEndsTheSession() async throws {
        StubURLProtocol.reset { request in
            if (request.url?.path() ?? "").hasSuffix("auth/refresh") {
                return (401, Data(#"{"error":{"code":"token_reused"}}"#.utf8))
            }
            return (401, Data())
        }
        let (ended, onEnded) = AsyncStream.makeStream(of: Void.self)
        let (client, tokens) = makeClient(onSessionExpired: onEnded)
        await #expect(throws: AppError.sessionExpired) {
            let _: User = try await client.get("v1/me")
        }
        #expect(tokens.refreshToken == nil)
        let told = await timesTold(ended, onEnded)
        #expect(told == 1)
    }

    /// An outage or a rate limit is not a refused session: nobody is signed out by one.
    @Test(arguments: [429, 500, 503])
    func aRefreshThatFailsOnTheServerKeepsTheSession(status: Int) async throws {
        StubURLProtocol.reset { request in
            if (request.url?.path() ?? "").hasSuffix("auth/refresh") {
                return (status, Data(#"{"error":{"code":"server_error"}}"#.utf8))
            }
            return (401, Data())
        }
        let (ended, onEnded) = AsyncStream.makeStream(of: Void.self)
        let (client, tokens) = makeClient(onSessionExpired: onEnded)
        do {
            let _: User = try await client.get("v1/me")
            Issue.record("The request should have failed")
        } catch {
            #expect((error as? AppError) != AppError.sessionExpired)
        }
        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
        let told = await timesTold(ended, onEnded)
        #expect(told == 0)
    }

    @Test func signingInSendsTheNonceAndKeepsTheSession() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"access_token":"a","refresh_token":"r","expires_in":900,"user":{"id":"u_1","username":"patdoe","name":"","is_admin":false}}"#.utf8))
        }
        let (client, tokens) = makeClient()
        tokens.clear()
        let api = LiveAPI(client: client)
        let outcome = try await api.signIn(identityToken: "identity", nonce: "nonce-1", fullName: nil)
        guard case .signedIn(let user) = outcome else {
            Issue.record("A returning person should be signed in")
            return
        }
        #expect(user.username == "patdoe")
        #expect(tokens.refreshToken == "r")

        let sent = try #require(StubURLProtocol.requests.withLock { $0.first })
        #expect(sent.url?.path() == "/v1/auth/apple")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func someoneNewGetsATicketAndNoSession() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"signup_ticket":"ticket-1","expires_in":600}"#.utf8))
        }
        let (client, tokens) = makeClient()
        tokens.clear()
        let api = LiveAPI(client: client)
        let outcome = try await api.signIn(identityToken: "identity", nonce: "nonce-1", fullName: "Pat Doe")
        #expect(outcome == .newAccount(ticket: "ticket-1"))
        #expect(!tokens.hasSession)
    }
}
