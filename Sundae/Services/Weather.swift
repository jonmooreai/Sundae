import Foundation

/// Is it a day for indoors? One anonymous request to Open-Meteo for the middle of the cell,
/// no key and no account. Anything that fails or takes too long counts as a dry day.
enum Weather {
    enum Sky: Sendable {
        case clear, cloudy, wet
    }

    private struct Response: Decodable {
        struct Current: Decodable { let weatherCode: Int }
        let current: Current
    }

    static func sky(latitude: Double, longitude: Double) async -> Sky? {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=weather_code") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let result = try? await URLSession.shared.data(for: request) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let response = try? decoder.decode(Response.self, from: result.0) else { return nil }
        return sky(forCode: response.current.weatherCode)
    }

    /// WMO weather codes: 0 clear, 1 to 48 cloud and fog, anything above is falling from the sky.
    static func sky(forCode code: Int) -> Sky {
        switch code {
        case 0: .clear
        case 1...48: .cloudy
        default: .wet
        }
    }
}
