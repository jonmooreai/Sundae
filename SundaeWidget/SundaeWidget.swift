import SwiftUI
import WidgetKit

/// The widget is the best version of the weekday screen: the suggestion and days until Sunday,
/// without opening the app at all. On Sunday it says so and nothing else.
struct SuggestionEntry: TimelineEntry {
    let date: Date
    let suggestion: Suggestion?
    let daysUntilSunday: Int
    let isSunday: Bool
    let hasPosted: Bool
    let pendingApprovals: Int
}

struct SuggestionProvider: TimelineProvider {
    private let catalog = SuggestionCatalog.bundled()
    private let shared = SharedDefaults()

    func placeholder(in context: Context) -> SuggestionEntry {
        SuggestionEntry(date: Date(),
                        suggestion: Suggestion(id: "p", text: "Walk a neighborhood you don't know.",
                                               reason: "Pick a direction and take the first street that looks interesting.",
                                               categories: [.outdoors], timeOfDay: .any),
                        daysUntilSunday: 4, isSunday: false, hasPosted: false, pendingApprovals: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (SuggestionEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SuggestionEntry>) -> Void) {
        let clock = SundayClock()
        var entries: [SuggestionEntry] = [entry(for: clock.now())]
        // One entry per upcoming day boundary for a week, plus the time-of-day changes today.
        let today = clock.calendar.startOfDay(for: clock.now())
        for hour in [12, 17] {
            if let d = clock.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today), d > clock.now() {
                entries.append(entry(for: d))
            }
        }
        for day in 1...7 {
            if let d = clock.calendar.date(byAdding: .day, value: day, to: today) {
                entries.append(entry(for: d))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> SuggestionEntry {
        let clock = SundayClock(now: { date })
        let isSunday = clock.isSunday()
        let suggestion: Suggestion?
        if let id = shared.currentSuggestionID(on: date, calendar: clock.calendar),
           let s = shared.localIdeas(on: date, calendar: clock.calendar)?.first(where: { $0.id == id }) ?? catalog.suggestion(id: id) {
            suggestion = s
        } else {
            suggestion = catalog.suggestion(forDay: date, calendar: clock.calendar)
        }
        let posted = shared.postedWeekStart.map { $0 == clock.weekStart() } ?? false
        return SuggestionEntry(date: date, suggestion: suggestion, daysUntilSunday: clock.daysUntilSunday(),
                               isSunday: isSunday, hasPosted: posted, pendingApprovals: shared.pendingApprovalCount)
    }
}

struct SundaeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SuggestionEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isSunday ? "Sundae" : countdown)
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(entry.isSunday ? (entry.hasPosted ? "Your week is up." : "Post your week.") : (entry.suggestion?.text ?? ""))
                    .font(.caption)
                    .lineLimit(2)
            }
        default:
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.isSunday ? "It's Sunday" : countdown)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if entry.pendingApprovals > 0 {
                    Text("\(entry.pendingApprovals)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            Spacer(minLength: 0)
            if entry.isSunday {
                Text(entry.hasPosted ? "Your week is up." : "Post your week.")
                    .font(.system(.title3, design: .serif, weight: .semibold))
            } else {
                Text(entry.suggestion?.text ?? "Go make something worth posting.")
                    .font(.system(family == .systemSmall ? .subheadline : .title3, design: .serif, weight: .semibold))
                    .minimumScaleFactor(0.7)
                if family != .systemSmall, let reason = entry.suggestion?.reason {
                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var countdown: String {
        entry.daysUntilSunday == 1 ? "Sunday is tomorrow" : "\(entry.daysUntilSunday) days until Sunday"
    }

    private var inlineText: String {
        if entry.isSunday { return entry.hasPosted ? "Sundae: your week is up" : "Sundae: post your week" }
        return "Sundae: \(countdown.lowercased())"
    }
}

struct SundaeWidget: Widget {
    let kind = "SundaeSuggestion"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SuggestionProvider()) { entry in
            SundaeWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hue: 0.08, saturation: 0.18, brightness: 1.0), Color(uiColor: .systemBackground)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Today's idea")
        .description("One thing to go do this week, and how long until Sunday.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct SundaeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SundaeWidget()
    }
}
