import SwiftUI

/// Fifty-two small squares, one per week, oldest first, filled with that week's first photo.
/// Empty weeks stay cream. By December it is the most personal poster anyone owns.
struct YearInWeeks: View {
    @Environment(AppModel.self) private var model
    let profile: Profile

    private static let columns = 13

    var body: some View {
        let starts = model.clock.recentWeekStarts(count: 52).reversed()
        let filled = starts.filter { start in profile.weeks.first { $0.weekStart == start }?.dump != nil }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("A year in weeks").font(.footnote.weight(.semibold))
                Text("\(filled) of 52").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                YearShareButton(profile: profile)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: Self.columns), spacing: 4) {
                ForEach(Array(starts.enumerated()), id: \.offset) { index, start in
                    let week = profile.weeks.first { $0.weekStart == start }
                    if let dump = week?.dump, let photo = dump.photos.min(by: { $0.order < $1.order }) {
                        NavigationLink(value: Route.dump(dump.id, photo: photo.id)) {
                            PhotoView(source: photo.source)
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Week of \(model.clock.rangeLabel(weekStart: start))")
                        .modifier(RiseIn(delay: Double(index) * 0.008))
                    } else {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(start == model.currentWeekStart ? Theme.fill : Theme.surface)
                            .aspectRatio(1, contentMode: .fit)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}
