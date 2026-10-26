import Foundation
import Synchronization
import Testing
@testable import Sundae

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

@Suite(.serialized)
struct HTTPClientTests {
    private func makeClient(onSessionExpired: AsyncStream<Void>.Continuation? = nil) -> (HTTPClient, TokenStore) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let tokens = TokenStore(storage: InMemorySecretStorage())
        tokens.store(accessToken: "access-1", refreshToken: "refresh-1", expiresIn: 3600)
        let client = HTTPClient(baseURL: URL(string: "https://api.sundae.test")!, tokens: tokens,
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

    @Test func serverErrorCodesBecomeSundaeErrors() async throws {
        StubURLProtocol.reset { _ in
            (423, Data(#"{"error":{"code":"sunday_closed","message":"Come back Sunday."}}"#.utf8))
        }
        let (client, _) = makeClient()
        await #expect(throws: SundaeError.sundayClosed) {
            let _: [DTO.Dump] = try await client.get("v1/feed")
        }
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
        let dumps: [DTO.Dump] = try await client.get("v1/feed")
        #expect(dumps.isEmpty)

        let paths = StubURLProtocol.requests.withLock { $0.map { $0.url?.path() ?? "" } }
        #expect(paths.filter { $0.hasSuffix("auth/refresh") }.count == 1)
        #expect(paths.filter { $0.hasSuffix("v1/feed") }.count == 2)
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
        await #expect(throws: SundaeError.sessionExpired) {
            let _: DTO.User = try await client.get("v1/me")
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
            let _: DTO.User = try await client.get("v1/me")
            Issue.record("The request should have failed")
        } catch {
            #expect((error as? SundaeError) != SundaeError.sessionExpired)
        }
        #expect(tokens.accessToken == "access-1")
        #expect(tokens.refreshToken == "refresh-1")
        let told = await timesTold(ended, onEnded)
        #expect(told == 0)
    }
}

struct DTOTests {
    @Test func dumpDecodesIntoTheAppModel() throws {
        let json = """
        {
          "id": "d_1", "week_start": "2026-10-19", "caption": "Bikes.", "created_at": "2026-10-25T13:05:00Z",
          "locked_at": null, "comments_enabled": true, "liked_by_me": false, "comment_count": 2,
          "author": {"id": "u_maya", "username": "maya", "name": "Maya Chen", "bio": null, "avatar_url": null, "is_public": false},
          "liked_by": [{"id": "u_theo", "username": "theo", "name": "Theo Park", "is_public": false}],
          "photos": [
            {"id": "p_2", "dump_id": "d_1", "order": 1, "url": "https://cdn.sundae.test/p_2?sig=x", "width": 1200, "height": 1600, "alt_text": null,
             "tags": []},
            {"id": "p_1", "dump_id": "d_1", "order": 0, "url": "https://cdn.sundae.test/p_1?sig=x", "width": 1600, "height": 1200, "alt_text": "Market",
             "tags": [{"id": "t_1", "photo_id": "p_1", "tagger_id": "u_maya", "status": "pending", "responded_at": null,
                       "tagged_user": {"id": "u_me", "username": "jon", "is_public": false}}]}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let dump = try decoder.decode(DTO.Dump.self, from: Data(json.utf8)).model

        #expect(dump.author.displayName == "Maya Chen")
        #expect(dump.photos.map(\.id) == ["p_1", "p_2"])
        #expect(dump.photos[0].visibleTags.first?.taggedUser.username == "jon")
        #expect(dump.likedBy.first?.firstName == "Theo")
        #expect(DTO.weekString(dump.weekStart) == "2026-10-19")
    }

    @Test func aSettingsSaveSendsOnlyWhatChanged() throws {
        var wanted = AccountSettings()
        wanted.isPublic = true
        wanted.autoApproveUserIDs = ["u_pat"]
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(DTO.SettingsPatch(AccountSettingsPatch(from: AccountSettings(), to: wanted)))
        #expect(String(decoding: data, as: UTF8.self) == #"{"auto_approve_user_ids":["u_pat"],"is_public":true}"#)
    }

    @Test func pendingPostRoundTripsThroughDisk() throws {
        let store = PendingPostStore()
        defer { store.clear() }
        let photo = DraftPhoto(source: .data(Data([0xFF, 0xD8, 0xFF])), width: 10, height: 10, altText: "Bread")
        let post = PendingPost(weekStart: Date(timeIntervalSince1970: 1_792_000_000), draft: DumpDraft(photos: [photo], caption: "Soup."), queuedAt: Date())
        store.save(post)
        let loaded = store.load()
        #expect(loaded?.draft == post.draft)
        #expect(loaded?.weekStart == post.weekStart)
    }
}
