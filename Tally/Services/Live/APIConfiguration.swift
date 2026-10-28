import Foundation

/// Where the app points. With no server address configured the app runs on `MockAPI`.
///
/// Set `APIBaseURL` in project.yml (Info.plist), or `API_BASE_URL` in the scheme's environment, to
/// use the live client. Pass `-mockAPI` as a launch argument to force demo data regardless. No
/// secrets live here: the address is public and tokens are made per device at sign-in.
enum APIConfiguration {
    static var baseURL: URL? {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-mockAPI") { return nil }
        let fromEnvironment = process.environment["API_BASE_URL"]
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
        guard let raw = [fromEnvironment, fromPlist].compactMap({ $0 }).first(where: { !$0.isEmpty }),
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
}
