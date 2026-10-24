import Foundation

/// Where the app points. With no base URL configured the app runs against `MockSundaeAPI`.
///
/// Set `SUNDAE_API_BASE_URL` in the scheme's environment, or `SundaeAPIBaseURL` in Info.plist,
/// to use the live client. Pass `-mockAPI` as a launch argument to force the mock regardless.
/// No secrets live here: the base URL is public and tokens are minted per device at sign-in.
enum APIConfiguration {
    static var baseURL: URL? {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-mockAPI") { return nil }
        let fromEnvironment = process.environment["SUNDAE_API_BASE_URL"]
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "SundaeAPIBaseURL") as? String
        guard let raw = [fromEnvironment, fromPlist].compactMap({ $0 }).first(where: { !$0.isEmpty }),
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
}
