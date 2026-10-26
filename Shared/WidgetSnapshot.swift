import Foundation
import Photos
import UIKit

/// Everything a Sundae widget draws, built the same way in the widget and in the app's Settings
/// preview, so the preview is the widget.
public struct WidgetSnapshot: Sendable, Equatable {
    public enum Mode: String, Sendable, Hashable, CaseIterable {
        case weekday, sunday
    }

    /// One later day this week: "Thu" and its idea, or "Sun" and the nudge to post.
    public struct Upcoming: Sendable, Hashable {
        public let day: String
        public let text: String
    }

    public var mode: Mode
    /// "Wednesday".
    public var dayName: String
    public var daysUntilSunday: Int
    public var idea: Suggestion?
    public var upcoming: [Upcoming]
    /// Small JPEGs of a few photos from this week, oldest first. Empty without Photos access.
    public var photos: [Data]
    /// How many photos the library holds from Monday until now.
    public var weekPhotoCount: Int
    public var hasPosted: Bool

    /// "4 days to Sunday", "Sunday is tomorrow".
    public var countdown: String {
        switch daysUntilSunday {
        case 0: "It's Sunday"
        case 1: "Sunday is tomorrow"
        default: "\(daysUntilSunday) days to Sunday"
        }
    }

    public static let placeholder = WidgetSnapshot(
        mode: .weekday, dayName: "Wednesday", daysUntilSunday: 4,
        idea: Suggestion(id: "placeholder", text: "Walk a neighborhood you don't know.",
                         reason: "Pick a direction and take the first street that looks interesting.",
                         categories: [.outdoors], timeOfDay: .any),
        upcoming: [Upcoming(day: "Thu", text: "Find the oldest book in the library."),
                   Upcoming(day: "Fri", text: "Cook something you can't pronounce.")],
        photos: [], weekPhotoCount: 0, hasPosted: false)
}

public enum WidgetSnapshotBuilder {
    /// The snapshot for `date`. `mode` forces weekday or Sunday for the Settings preview; the
    /// widget leaves it nil and lets the calendar decide.
    public static func snapshot(at date: Date, timeZone: TimeZone = .current, mode: WidgetSnapshot.Mode? = nil,
                                catalog: SuggestionCatalog, shared: SharedDefaults,
                                photos: (thumbnails: [Data], count: Int) = ([], 0)) -> WidgetSnapshot {
        let clock = SundayClock(now: { date }, timeZone: timeZone)
        let calendar = clock.calendar
        let resolved = mode ?? (clock.isSunday() ? .sunday : .weekday)
        let posted = shared.postedWeekStart.map { $0 == clock.weekStart() } ?? false
        return WidgetSnapshot(
            mode: resolved,
            dayName: clock.weekdayName(date),
            daysUntilSunday: clock.daysUntilSunday(),
            idea: idea(on: date, calendar: calendar, catalog: catalog, shared: shared),
            upcoming: upcoming(after: date, clock: clock, catalog: catalog),
            photos: photos.thumbnails,
            weekPhotoCount: photos.count,
            hasPosted: posted)
    }

    /// The idea the app is showing today: the one picked or shuffled to, a nearby one if the
    /// app has today's, otherwise the catalog's pick for the day. Same order as the app.
    static func idea(on date: Date, calendar: Calendar, catalog: SuggestionCatalog, shared: SharedDefaults) -> Suggestion? {
        let local = shared.localIdeas(on: date, calendar: calendar) ?? []
        if let id = shared.currentSuggestionID(on: date, calendar: calendar),
           let current = local.first(where: { $0.id == id }) ?? catalog.suggestion(id: id),
           IdeaGuard.isSafe(current) {
            return current
        }
        let slot = Suggestion.TimeOfDay.current(for: date, calendar: calendar)
        if let nearby = local.first(where: { $0.timeOfDay == slot || $0.timeOfDay == .any }) ?? local.first {
            return nearby
        }
        return catalog.suggestion(forDay: date, calendar: calendar)
    }

    /// The next two days: their catalog ideas, or Sunday's nudge when Sunday comes first.
    static func upcoming(after date: Date, clock: SundayClock, catalog: SuggestionCatalog) -> [WidgetSnapshot.Upcoming] {
        let calendar = clock.calendar
        let short = DateFormatter()
        short.calendar = calendar
        short.timeZone = calendar.timeZone
        short.setLocalizedDateFormatFromTemplate("EEE")
        var result: [WidgetSnapshot.Upcoming] = []
        let today = calendar.startOfDay(for: date)
        for offset in 1...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if clock.isSunday(day) {
                result.append(.init(day: short.string(from: day), text: "Post your week."))
                break
            }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            if let idea = catalog.suggestion(forDay: noon, calendar: calendar) {
                result.append(.init(day: short.string(from: day), text: idea.text))
            }
        }
        return result
    }
}

/// A few photos from this week, read straight from the library with the app's own Photos
/// access. Nothing is copied anywhere; without access the widget shows the sundae instead.
public enum WidgetPhotos {
    public static var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Up to `limit` photos spread across the week (favorites first), as small JPEGs.
    /// Synchronous: call it off the main thread.
    public static func thisWeek(weekStart: Date, until end: Date, limit: Int = 3, side: CGFloat = 360) -> (thumbnails: [Data], count: Int) {
        guard isAuthorized else { return ([], 0) }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND (mediaSubtypes & %d) == 0",
            weekStart as NSDate, end as NSDate, Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        let count = result.count
        guard count > 0 else { return ([], 0) }

        let picks = pick(result.objects(at: IndexSet(integersIn: 0..<count)), limit: limit)

        let manager = PHImageManager.default()
        let request = PHImageRequestOptions()
        request.isSynchronous = true
        request.deliveryMode = .highQualityFormat
        request.resizeMode = .fast
        request.isNetworkAccessAllowed = false
        var thumbnails: [Data] = []
        for asset in picks {
            // Synchronous request: the handler runs before requestImage returns.
            let box = DataBox()
            manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                 contentMode: .aspectFill, options: request) { image, _ in
                box.data = image?.jpegData(compressionQuality: 0.8)
            }
            if let data = box.data { thumbnails.append(data) }
        }
        return (thumbnails, count)
    }

    private final class DataBox: @unchecked Sendable {
        var data: Data?
    }

    /// Favorites first, then evenly spaced through the week, kept in the order they were taken.
    /// The same library gives the same picks, so the widget does not flicker between refreshes.
    static func pick(_ assets: [PHAsset], limit: Int) -> [PHAsset] {
        guard assets.count > limit else { return assets }
        var chosen = assets.filter(\.isFavorite).suffix(limit).map(\.localIdentifier)
        let remaining = limit - chosen.count
        if remaining > 0 {
            let others = assets.filter { !chosen.contains($0.localIdentifier) }
            let step = Double(others.count) / Double(remaining)
            for i in 0..<remaining {
                let index = min(others.count - 1, Int(Double(i) * step + step / 2))
                chosen.append(others[index].localIdentifier)
            }
        }
        let set = Set(chosen)
        return assets.filter { set.contains($0.localIdentifier) }
    }
}
