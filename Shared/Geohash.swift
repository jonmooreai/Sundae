import Foundation

/// Geohash encoding, used to turn a precise position into a neighborhood-sized cell before it
/// leaves the phone. Six characters cover about 1.2 km by 0.6 km; five about 4.9 km square.
/// Base32 cells are also good cache keys: everyone standing in one asks the same question.
public enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    public static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        let lat = min(max(latitude, -90), 90)
        let lon = min(max(longitude, -180), 180)
        var latRange = (low: -90.0, high: 90.0)
        var lonRange = (low: -180.0, high: 180.0)
        var hash = ""
        var bits = 0
        var value = 0
        var evenBit = true
        while hash.count < max(precision, 1) {
            if evenBit {
                let mid = (lonRange.low + lonRange.high) / 2
                if lon >= mid { value = value * 2 + 1; lonRange.low = mid } else { value *= 2; lonRange.high = mid }
            } else {
                let mid = (latRange.low + latRange.high) / 2
                if lat >= mid { value = value * 2 + 1; latRange.low = mid } else { value *= 2; latRange.high = mid }
            }
            evenBit.toggle()
            bits += 1
            if bits == 5 {
                hash.append(base32[value])
                bits = 0
                value = 0
            }
        }
        return hash
    }
}
