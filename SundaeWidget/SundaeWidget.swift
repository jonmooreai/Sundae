import SwiftUI
import WidgetKit

/// Monday to Saturday the widget is the best version of the weekday screen: today's idea, and on
/// the large size a few more to read through, nearby ones a tap from Apple Maps. On Sunday it
/// turns to a few of this week's photos and a nudge to post. Small, wide and large on the Home
/// Screen, plus the Lock Screen sizes.
struct SundaeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SundaeProvider: TimelineProvider {
    private let catalog = SuggestionCatalog.bundled()
    private let shared = SharedDefaults()

    func placeholder(in context: Context) -> SundaeEntry {
        SundaeEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SundaeEntry) -> Void) {
        let now = Date()
        completion(entry(at: now, photos: weekPhotos(until: now)))
    }

    /// Weekdays: an entry at midnight, noon and five each day until Sunday begins, then a fresh
    /// timeline on Sunday so the photos are Sunday's. Sundays: refreshed hourly for new photos.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SundaeEntry>) -> Void) {
        let clock = SundayClock()
        let calendar = clock.calendar
        let now = clock.now()
        let photos = weekPhotos(until: now)

        var dates: [Date] = [now]
        let boundary = clock.nextBoundary(after: now)
        var day = calendar.startOfDay(for: now)
        while day <= boundary {
            for hour in [0, 12, 17] {
                if let moment = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                   moment > now, moment <= boundary {
                    dates.append(moment)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        let entries = dates.map { entry(at: $0, photos: photos) }
        let refresh = clock.isSunday(now)
            ? min(now.addingTimeInterval(3600), boundary.addingTimeInterval(60))
            : boundary.addingTimeInterval(60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry(at date: Date, photos: (thumbnails: [Data], count: Int)) -> SundaeEntry {
        SundaeEntry(date: date, snapshot: WidgetSnapshotBuilder.snapshot(
            at: date, catalog: catalog, shared: shared, photos: photos))
    }

    private func weekPhotos(until date: Date) -> (thumbnails: [Data], count: Int) {
        let clock = SundayClock(now: { date })
        return WidgetPhotos.thisWeek(weekStart: clock.weekStart(), until: date)
    }
}

struct SundaeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SundaeEntry

    var body: some View {
        SundaeWidgetView(snapshot: entry.snapshot, family: family)
    }
}

struct SundaeWidget: Widget {
    let kind = "SundaeSuggestion"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SundaeProvider()) { entry in
            SundaeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) { WidgetPalette.paper }
        }
        .configurationDisplayName("Sundae")
        .description("Monday to Saturday, ideas worth doing, some near you. On Sunday, a few of this week's photos and a nudge to post.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct SundaeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SundaeWidget()
    }
}
