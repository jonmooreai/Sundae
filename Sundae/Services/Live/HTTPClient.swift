import Foundation

/// Thin JSON-over-HTTPS layer: builds requests, attaches the bearer token, refreshes it
/// once on expiry or a 401 (single-flight), and maps server error codes to `SundaeError`.
///
/// TLS stays at App Transport Security defaults. No certificate pinning, by decision.
actor HTTPClient {
    struct Empty: Codable {}

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
            let message: String?
        }
        let error: Body
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
    }

    let baseURL: URL
    let tokens: TokenStore
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var refreshTask: Task<Void, Error>?

    private static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    init(baseURL: URL, tokens: TokenStore = TokenStore(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = (try? Self.isoFractional.parse(string)) ?? (try? Self.isoPlain.parse(string)) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date \(string)"))
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.isoFractional.format(date))
        }
        self.encoder = encoder
    }

    // MARK: - Requests

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> Response {
        try await send("GET", path, query: query, body: Optional<Empty>.none, authenticated: authenticated)
    }

    func post<Response: Decodable>(_ path: String, authenticated: Bool = true) async throws -> Response {
        try await send("POST", path, body: Optional<Empty>.none, authenticated: authenticated)
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, authenticated: Bool = true) async throws -> Response {
        try await send("POST", path, body: Optional(body), authenticated: authenticated)
    }

    func put<Response: Decodable>(_ path: String) async throws -> Response {
        try await send("PUT", path, body: Optional<Empty>.none, authenticated: true)
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send("PUT", path, body: Optional(body), authenticated: true)
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send("PATCH", path, body: Optional(body), authenticated: true)
    }

    func delete<Response: Decodable>(_ path: String) async throws -> Response {
        try await send("DELETE", path, body: Optional<Empty>.none, authenticated: true)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Body?, authenticated: Bool
    ) async throws -> Response {
        var request = try makeRequest(method, path, query: query, body: body)
        if authenticated {
            let token = try await validAccessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var (data, response) = try await perform(request)
        if authenticated, response.statusCode == 401 {
            try await refresh()
            let token = try await validAccessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            (data, response) = try await perform(request)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw mapError(status: response.statusCode, data: data)
        }
        if data.isEmpty, let empty = Empty() as? Response { return empty }
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest<Body: Encodable>(_ method: String, _ path: String, query: [URLQueryItem], body: Body?) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw SundaeError.notFound }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SundaeError.offline }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw SundaeError.offline
            default:
                throw error
            }
        }
    }

    private func mapError(status: Int, data: Data) -> Error {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
            switch envelope.error.code {
            case "sunday_closed": return SundaeError.sundayClosed
            case "dump_locked": return SundaeError.dumpLocked
            case "too_many_photos": return SundaeError.tooManyPhotos
            case "too_many_tags": return SundaeError.tooManyTags
            case "caption_too_long": return SundaeError.captionTooLong
            case "invalid_code": return SundaeError.invalidCode
            case "not_found": return SundaeError.notFound
            case "forbidden": return SundaeError.notAuthorized
            case "username_taken": return SundaeError.usernameTaken
            case "invalid_username": return SundaeError.invalidUsername
            case "signups_closed": return SundaeError.signupsClosed
            case "account_exists": return SundaeError.signInAgain
            default: break
            }
        }
        switch status {
        case 401, 403: return SundaeError.notAuthorized
        case 404: return SundaeError.notFound
        case 423: return SundaeError.dumpLocked
        default: return SundaeError.notFound
        }
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Sundae/\(version) (\(build); iOS)"
    }()

    // MARK: - Tokens

    func storeTokens(_ response: TokenResponse) {
        tokens.store(accessToken: response.accessToken, refreshToken: response.refreshToken, expiresIn: response.expiresIn)
    }

    func clearTokens() {
        tokens.clear()
    }

    var hasSession: Bool { tokens.hasSession }

    private func validAccessToken() async throws -> String {
        if let token = tokens.accessToken, let expiry = tokens.accessExpiry, expiry > Date().addingTimeInterval(30) {
            return token
        }
        try await refresh()
        guard let token = tokens.accessToken else { throw SundaeError.notAuthorized }
        return token
    }

    /// One refresh at a time. Concurrent callers wait on the same task.
    private func refresh() async throws {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func performRefresh() async throws {
        guard let refreshToken = tokens.refreshToken else { throw SundaeError.notAuthorized }
        struct Body: Encodable { let refreshToken: String }
        let request = try makeRequest("POST", "v1/auth/refresh", query: [], body: Optional(Body(refreshToken: refreshToken)))
        let (data, response) = try await perform(request)
        guard (200..<300).contains(response.statusCode) else {
            // A rejected refresh means the family was revoked or expired. The session is over.
            tokens.clear()
            throw SundaeError.notAuthorized
        }
        storeTokens(try decoder.decode(TokenResponse.self, from: data))
    }
}
