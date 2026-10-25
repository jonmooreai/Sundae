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

    /// The box a cell covers, or nil for a string that is not a geohash.
    public static func bounds(_ hash: String) -> (latitude: ClosedRange<Double>, longitude: ClosedRange<Double>)? {
        var latRange = (low: -90.0, high: 90.0)
        var lonRange = (low: -180.0, high: 180.0)
        var evenBit = true
        for character in hash.lowercased() {
            guard let index = base32.firstIndex(of: character) else { return nil }
            for bit in stride(from: 4, through: 0, by: -1) {
                let on = (index >> bit) & 1 == 1
                if evenBit {
                    let mid = (lonRange.low + lonRange.high) / 2
                    if on { lonRange.low = mid } else { lonRange.high = mid }
                } else {
                    let mid = (latRange.low + latRange.high) / 2
                    if on { latRange.low = mid } else { latRange.high = mid }
                }
                evenBit.toggle()
            }
        }
        return (latRange.low...latRange.high, lonRange.low...lonRange.high)
    }

    public static func center(_ hash: String) -> (latitude: Double, longitude: Double)? {
        guard let box = bounds(hash) else { return nil }
        return ((box.latitude.lowerBound + box.latitude.upperBound) / 2,
                (box.longitude.lowerBound + box.longitude.upperBound) / 2)
    }
}
