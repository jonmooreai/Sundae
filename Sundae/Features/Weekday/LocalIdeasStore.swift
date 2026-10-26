import CoreLocation
import Foundation
import Observation
import WidgetKit

/// Ideas for the neighborhood the phone is in, Monday to Saturday, if the user asked for them.
///
/// The rules this type keeps, in order: nothing happens unless the user turned it on; nothing
/// happens on Sunday, whatever is turned on; the position is reduced to a cell on the phone and
/// discarded; the request carries no account; the answer is kept for the day, so location is
/// looked at a few times a day at most.
@MainActor
@Observable
final class LocalIdeasStore {
    enum Status: Equatable {
        case off
        /// On, and iOS has not asked the user yet. The system prompt shows on the first look.
        case waitingForPermission
        /// On, but iOS says no for this app.
        case denied
        case locating
        case loading
        /// Today's ideas are in hand. Zero means a quiet area.
        case ready(count: Int)
        case offline
        case failed
    }

    private let api: any SundaeAPI
    /// True when ideas come from Apple Maps on the phone (no Sundae server involved at all);
    /// false when a server is configured and `api.localIdeas` answers.
    private let onDevice: Bool
    private let shared: SharedDefaults
    private static let enabledKey = "localIdeas.enabled"

    private(set) var isEnabled: Bool
    private(set) var status: Status
    /// Today's ideas for the area. Empty when off, on Sunday, or when nothing is nearby.
    private(set) var ideas: [Suggestion] = []
    private var inFlight: Task<Void, Never>?

    init(api: any SundaeAPI, onDevice: Bool, shared: SharedDefaults = SharedDefaults()) {
        self.api = api
        self.onDevice = onDevice
        self.shared = shared
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        status = enabled ? .loading : .off
    }

    var isDenied: Bool { LocationCell.isDenied }

    /// Called after the consent sheet, never before.
    func enable() {
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        switch LocationCell.authorization {
        case .notDetermined: status = .waitingForPermission
        case .denied, .restricted: status = .denied
        default: status = .loading
        }
    }

    /// Off, and nothing about the area stays on the phone.
    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        inFlight?.cancel()
        inFlight = nil
        ideas = []
        shared.clearLocalIdeas()
        status = .off
    }

    /// Loads today's ideas when allowed and needed. Safe to call on every appearance: it does
    /// nothing on Sunday, when off, when iOS said no, or when today's ideas are still fresh.
    func refresh(clock: SundayClock) async {
        guard isEnabled else { return }
        guard !clock.isSunday() else {
            // The rule. Sunday never looks, and shows nothing left over from Saturday.
            ideas = []
            return
        }
        let now = clock.now()
        if let cached = shared.localIdeas(on: now, calendar: clock.calendar) {
            ideas = cached
            status = .ready(count: cached.count)
        }
        guard LocalIdeasPolicy.shouldFetch(enabled: isEnabled, isSunday: false, lastFetch: shared.localIdeasFetchedAt,
                                           now: now, calendar: clock.calendar) else { return }
        if LocationCell.isDenied {
            status = .denied
            return
        }
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await fetch(clock: clock) }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func fetch(clock: SundayClock) async {
        status = .locating
        let cell: String
        do {
            cell = try await LocationCell.currentCell()
        } catch LocationCell.Failure.denied {
            status = .denied
            return
        } catch {
            status = .failed
            return
        }
        // Midnight may have passed, or the switch flipped, while waiting for the fix.
        guard !Task.isCancelled, isEnabled, !clock.isSunday() else { return }
        status = .loading
        do {
            let fresh = IdeaGuard.filter(onDevice
                ? try await NearbyIdeas.ideas(cell: cell, day: clock.now(), calendar: clock.calendar)
                : try await api.localIdeas(cell: cell, day: clock.now()))
            guard !Task.isCancelled, isEnabled else { return }
            ideas = fresh
            shared.setLocalIdeas(fresh, at: clock.now())
            WidgetCenter.shared.reloadAllTimelines()
            status = .ready(count: fresh.count)
        } catch SundaeError.offline {
            status = .offline
        } catch {
            status = .failed
        }
    }
}
