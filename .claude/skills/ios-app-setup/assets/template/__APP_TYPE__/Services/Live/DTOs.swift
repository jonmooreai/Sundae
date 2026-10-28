import Foundation

/// What goes over the wire, where it differs from the app's own models. Keys are converted to
/// snake_case by HTTPClient, so `identityToken` is sent as `identity_token`.
enum DTO {
    struct AppleSignIn: Encodable {
        let identityToken: String
        let nonce: String
        let fullName: String?
        let timezone: String
    }

    /// A session for someone coming back, or a ticket for someone new.
    struct AppleSignInResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: TimeInterval?
        let user: User?
        let signupTicket: String?

        var tokens: HTTPClient.TokenResponse? {
            guard let accessToken, let refreshToken, let expiresIn else { return nil }
            return HTTPClient.TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    struct AppleSignUp: Encodable {
        let signupTicket: String
        let username: String
        let name: String?
        let timezone: String
    }

    struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
        let user: User

        var tokens: HTTPClient.TokenResponse {
            HTTPClient.TokenResponse(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    struct NewNote: Encodable {
        let text: String
    }
}
