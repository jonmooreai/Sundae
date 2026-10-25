import Foundation
import SwiftUI

/// A faint warmth over the paper around sunset. Subtle enough to doubt, which is the point.
///
/// Sunset is estimated from the clock alone: the time zone's offset stands in for longitude
/// and a mid-latitude for latitude, so the app needs nothing about where the phone is.
enum GoldenHour {
    /// 0 outside golden hour, rising to 1 in the half hour before sunset, fading after.
    static func warmth(at date: Date, calendar: Calendar) -> Double {
        guard let sunset = approximateSunset(on: date, calendar: calendar) else { return 0 }
        let minutes = date.timeIntervalSince(sunset) / 60
        if minutes < -60 { return 0 }
        if minutes < -30 { return (minutes + 60) / 30 }
        if minutes < 10 { return 1 }
        if minutes < 30 { return (30 - minutes) / 20 }
        return 0
    }

    /// Local sunset for a mid-latitude place in this time zone, within half an hour or so.
    static func approximateSunset(on date: Date, calendar: Calendar) -> Date? {
        let zone = calendar.timeZone
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let latitude = 38.0 * .pi / 180
        let declination = 23.44 * .pi / 180 * sin(2 * .pi * (284 + dayOfYear) / 365)
        let cosHour = -tan(latitude) * tan(declination)
        guard abs(cosHour) <= 1 else { return nil }
        let hourAngle = acos(cosHour) * 180 / .pi / 15   // hours from solar noon to sunset
        let longitude = Double(zone.secondsFromGMT(for: date)) / 3600 * 15
        let sunsetUTC = 12 + hourAngle - longitude / 15    // hours, UTC
        let utcMidnight = calendar.startOfDay(for: date).addingTimeInterval(Double(zone.secondsFromGMT(for: date)))
        return utcMidnight.addingTimeInterval(sunsetUTC * 3600)
    }
}

/// Lays the warmth over whatever it wraps, re-checked once a minute.
private struct GoldenHourTint: ViewModifier {
    let calendar: Calendar

    func body(content: Content) -> some View {
        content.overlay {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let warmth = GoldenHour.warmth(at: context.date, calendar: calendar)
                Color(red: 1.0, green: 0.72, blue: 0.38)
                    .opacity(0.07 * warmth)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func goldenHour(calendar: Calendar) -> some View { modifier(GoldenHourTint(calendar: calendar)) }
}
