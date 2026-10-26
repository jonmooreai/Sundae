import CoreLocation
import Foundation

/// When the app may look at location at all. Pure, so the Sunday rule has a test.
enum LocalIdeasPolicy {
    /// How long a day's ideas stay fresh before another look, for people who move around.
    static let refreshInterval: TimeInterval = 4 * 60 * 60

    /// True only when the user opted in, it is not Sunday, and today's ideas are missing or stale.
    static func shouldFetch(enabled: Bool, isSunday: Bool, lastFetch: Date?, now: Date, calendar: Calendar) -> Bool {
        guard enabled, !isSunday else { return false }
        guard let lastFetch, calendar.isDate(lastFetch, inSameDayAs: now) else { return true }
        return now.timeIntervalSince(lastFetch) > refreshInterval
    }

    /// Cell size for what iOS granted: about a kilometer with precise location, about five with
    /// approximate location. Never finer than this, whatever the fix says.
    static func precision(accuracyLimited: Bool) -> Int {
        accuracyLimited ? 5 : 6
    }
}

/// One position, reduced to a geohash cell the moment it arrives. The coordinates live inside
/// `currentCell()` and nowhere else: not in a property, not in a log, not in a request.
enum LocationCell {
    enum Failure: Error, Equatable {
        case denied
        case unavailable
        case timedOut
    }

    @MainActor private static let manager = CLLocationManager()

    @MainActor static var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    @MainActor static var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Shows iOS's location prompt now, if this phone has never answered it, so it follows straight
    /// on from the yes in Sundae that explains it. While Using the App is all Sundae asks for. The
    /// answer is read the next time the weekday screen looks.
    @MainActor static func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Waits for one fix and returns its cell. If iOS has not asked the user yet, starting the
    /// updates shows the system prompt; the call then waits for the answer. Gives up after a while.
    static func currentCell(timeout seconds: Double = 60) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                        throw Failure.denied
                    }
                    if let location = update.location {
                        let precision = LocalIdeasPolicy.precision(accuracyLimited: update.accuracyLimited)
                        return Geohash.encode(latitude: location.coordinate.latitude,
                                              longitude: location.coordinate.longitude,
                                              precision: precision)
                    }
                }
                throw Failure.unavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw Failure.timedOut
            }
            guard let cell = try await group.next() else { throw Failure.unavailable }
            group.cancelAll()
            return cell
        }
    }
}
