import SwiftUI

/// The small cards that sometimes sit above the feed: a holiday's hello, a year ago today, a
/// friend's first Sunday, and the Sunday wrap after dark. Each shows once and goes away on its own.
struct FeedMoments: View {
    @Environment(AppModel.self) private var model
    let open: (Route) -> Void

    @State private var anniversary: Dump?
    @State private var dismissedAnniversary = false
    @State private var dismissedFirst: Set<ID> = []
    @State private var dismissedWrap = false
    @State private var dismissedHoliday: HolidaySunday?

    private var feed: FeedStore { model.feed }

    var body: some View {
        let firsts = firstSundays
        let wrap = wrapSummary
        let holiday = holidayToday
        if anniversary != nil && !dismissedAnniversary || !firsts.isEmpty || wrap != nil || holiday != nil {
            VStack(spacing: 12) {
                if let holiday {
                    HolidayCard(holiday: holiday) {
                        if model.holidayPreview == nil { MomentMemory.holidayShownWeekStart = model.currentWeekStart }
                        withAnimation { dismissedHoliday = holiday }
                    }
                }
                if let anniversary, !dismissedAnniversary {
                    AnniversaryCard(dump: anniversary, rangeLabel: model.clock.rangeLabel(weekStart: anniversary.weekStart)) {
                        open(.dump(anniversary.id))
                    } onDismiss: {
                        MomentMemory.anniversaryShownWeekStart = model.currentWeekStart
                        withAnimation { dismissedAnniversary = true }
                    }
                }
                ForEach(firsts) { dump in
                    FirstSundayCard(dump: dump) {
                        open(.dump(dump.id))
                    } onDismiss: {
                        MomentMemory.shownFirstSundays.insert(dump.id)
                        withAnimation { _ = dismissedFirst.insert(dump.id) }
                    }
                }
                if let wrap {
                    SundayWrapCard(summary: wrap) {
                        MomentMemory.wrapShownWeekStart = model.currentWeekStart
                        withAnimation { dismissedWrap = true }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .task { await loadAnniversary() }
        } else {
            Color.clear.frame(height: 0).task { await loadAnniversary() }
        }
    }

    /// A holiday Sunday's hello, until it is waved away. An admin's preview skips the once-a-week memory.
    private var holidayToday: HolidaySunday? {
        guard let holiday = model.holidayToday, holiday != dismissedHoliday else { return nil }
        if model.holidayPreview == nil, MomentMemory.holidayShownWeekStart == model.currentWeekStart { return nil }
        return holiday
    }

    /// Friends whose first week ever is in the feed, until you have seen the card.
    private var firstSundays: [Dump] {
        let shown = MomentMemory.shownFirstSundays
        return feed.dumps.filter { $0.isAuthorsFirst == true && !shown.contains($0.id) && !dismissedFirst.contains($0.id) }
    }

    /// After eight on Sunday evening, once, with tomorrow's idea at the end.
    private var wrapSummary: WrapSummary? {
        guard model.isSunday, !dismissedWrap, feed.hasLoaded else { return nil }
        let now = model.clock.now()
        guard model.clock.calendar.component(.hour, from: now) >= 20 else { return nil }
        if let shown = MomentMemory.wrapShownWeekStart, shown == model.currentWeekStart { return nil }
        let me = model.currentUser?.id
        let friends = feed.dumps.filter { $0.author.id != me }
        let mine = feed.dumps.first { $0.author.id == me }
        let tomorrow = model.clock.calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return WrapSummary(
            friendsPosted: friends.count,
            taggedIn: friends.filter { dump in dump.taggedUsers.contains { $0.id == me } }.count,
            firstLiker: mine?.likedBy.first { $0.id != me }?.firstName,
            posted: mine != nil,
            tomorrowsIdea: model.suggestions.suggestion(forDay: tomorrow, calendar: model.clock.calendar)?.text)
    }

    /// Your own week from exactly a year ago, if there was one, on Sunday only.
    private func loadAnniversary() async {
        guard model.isSunday, anniversary == nil else { return }
        if let shown = MomentMemory.anniversaryShownWeekStart, shown == model.currentWeekStart { return }
        guard let yearAgo = model.clock.calendar.date(byAdding: .day, value: -364, to: model.currentWeekStart) else { return }
        anniversary = try? await model.api.myDump(weekStart: yearAgo)
    }
}

struct WrapSummary: Equatable {
    let friendsPosted: Int
    let taggedIn: Int
    let firstLiker: String?
    let posted: Bool
    let tomorrowsIdea: String?

    var lines: [String] {
        var lines: [String] = []
        switch friendsPosted {
        case 0: lines.append("A quiet Sunday. Nobody you follow posted.")
        case 1: lines.append("One friend posted their week.")
        default: lines.append("\(friendsPosted) friends posted their weeks.")
        }
        if taggedIn > 0 { lines.append(taggedIn == 1 ? "You were in one of them." : "You were in \(taggedIn) of them.") }
        if let firstLiker { lines.append("\(firstLiker) was first to like yours.") }
        if !posted { lines.append("Yours is still open until midnight.") }
        return lines
    }
}

/// "Happy Halloween Sunday." with the jack-o'-lantern, or the day's own hello and felt piece, once.
struct HolidayCard: View {
    let holiday: HolidaySunday
    let onDismiss: () -> Void

    /// The felt piece on top, so the words get the card's full width.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                HolidayPiece(holiday: holiday, size: 52)
                    .modifier(RiseIn(delay: 0.1))
                Spacer(minLength: 0)
                IconButton(glyph: Glyph.close, label: "Dismiss", size: 18, action: onDismiss)
                    .padding(.trailing, -10)
                    .padding(.top, -8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(holiday.greeting).font(Theme.display(22))
                Text(holiday.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

/// The end-of-Sunday card: warm, not a dashboard, and it ends with Monday.
struct SundayWrapCard: View {
    let summary: WrapSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("That was Sunday.").font(Theme.display(24))
                Spacer()
                IconButton(glyph: Glyph.close, label: "Dismiss", size: 18, action: onDismiss)
                    .padding(.trailing, -10)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(summary.lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(.subheadline).modifier(RiseIn(delay: 0.1 + Double(index) * 0.1))
                }
            }
            if let idea = summary.tomorrowsIdea {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monday's idea").font(.caption.weight(.medium)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.6)
                    Text(idea).font(.subheadline.weight(.medium))
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }
}

/// "Lena's first Sunday." with their first photo. "You brought them here" when you did.
struct FirstSundayCard: View {
    let dump: Dump
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let photo = dump.photos.min(by: { $0.order < $1.order }) {
                Button(action: onOpen) {
                    PhotoView(source: photo.source)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(dump.author.firstName)'s first Sunday.").font(.subheadline.weight(.semibold))
                Text(dump.author.invitedByMe == true ? "You brought them here." : "Say hi in the comments.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            IconButton(glyph: Glyph.close, label: "Dismiss", size: 18, action: onDismiss)
                .padding(.trailing, -10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

/// "A year ago today": your week from 52 Sundays back, before the feed.
struct AnniversaryCard: View {
    let dump: Dump
    let rangeLabel: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("A year ago today").font(Theme.display(24))
                Spacer()
                IconButton(glyph: Glyph.close, label: "Dismiss", size: 18, action: onDismiss)
                    .padding(.trailing, -10)
            }
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    ForEach(dump.photos.sorted { $0.order < $1.order }.prefix(3)) { photo in
                        PhotoView(source: photo.source)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(height: 100)
            }
            .buttonStyle(.plain)
            Text(dump.caption.isEmpty ? rangeLabel : "\(rangeLabel). \(dump.caption)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
