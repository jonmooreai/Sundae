import Foundation

/// Thin JSON-over-HTTPS layer: builds requests, attaches the bearer token, refreshes it once on
/// expiry or a 401 (one refresh at a time, however many requests are waiting), and maps the
/// server's error codes to `AppError`. Keys are snake_case on the wire, camelCase in Swift.
///
/// TLS stays at App Transport Security defaults.
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
    /// Told once when the server refuses a refresh, so the app can sign out (AppModel).
    private let onSessionExpired: AsyncStream<Void>.Continuation?

    private static let isoFractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    init(baseURL: URL, tokens: TokenStore = TokenStore(), session: URLSession = .shared,
         onSessionExpired: AsyncStream<Void>.Continuation? = nil) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session
        self.onSessionExpired = onSessionExpired

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
        guard let url = components?.url else { throw AppError.notFound }
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
            guard let http = response as? HTTPURLResponse else { throw AppError.offline }
            return (data, http)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                throw AppError.offline
            default:
                throw error
            }
        }
    }

    private func mapError(status: Int, data: Data) -> Error {
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
            switch envelope.error.code {
            case "not_found": return AppError.notFound
            case "unauthorized": return AppError.notAuthorized
            case "username_taken": return AppError.usernameTaken
            case "invalid_username": return AppError.invalidUsername
            case "signups_closed": return AppError.signupsClosed
            case "account_exists": return AppError.signInAgain
            case "too_many": return AppError.tooMany
            default: break
            }
        }
        switch status {
        case 401, 403: return AppError.notAuthorized
        case 404: return AppError.notFound
        default: return AppError.server
        }
    }

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "Tally/\(version) (\(build); iOS)"
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
        guard let token = tokens.accessToken else { throw AppError.notAuthorized }
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
        guard let refreshToken = tokens.refreshToken else { throw AppError.notAuthorized }
        struct Body: Encodable { let refreshToken: String }
        let request = try makeRequest("POST", "v1/auth/refresh", query: [], body: Optional(Body(refreshToken: refreshToken)))
        let (data, response) = try await perform(request)
        if response.statusCode == 401 {
            // The server refused it: the session was revoked or ran out. It is over.
            tokens.clear()
            onSessionExpired?.yield(())
            throw AppError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode) else {
            // A server error says nothing about the session. Keep it for a later try.
            throw mapError(status: response.statusCode, data: data)
        }
        storeTokens(try decoder.decode(TokenResponse.self, from: data))
    }
}
