import SwiftUI

/// One week on a profile: date range, then a 160 pt strip of photos with a 4 pt gap.
/// Own photos first, then tagged photos with a "from Maya" chip. Captions show on tap only,
/// except your own current week, which shows its caption inline so you can see what you wrote.
struct WeekRow: View {
    @Environment(AppModel.self) private var model
    let week: ProfileWeek
    let isOwn: Bool
    let isCurrent: Bool
    let onRemoveTagged: (TaggedPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(isCurrent ? "This week" : model.clock.rangeLabel(weekStart: week.weekStart))
                    .font(.subheadline.weight(.semibold))
                if isCurrent {
                    Text(model.clock.rangeLabel(weekStart: week.weekStart))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isOwn, isCurrent, week.dump == nil, model.isSunday {
                    Text("Not posted yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            if isOwn, isCurrent, let caption = week.dump?.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.pagePadding)
            }

            if week.isEmpty {
                Text(isOwn && isCurrent ? "Post your week from the Post tab." : "No photos this week.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, Theme.pagePadding)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.gap) {
                        if let dump = week.dump {
                            ForEach(dump.photos.sorted { $0.order < $1.order }) { photo in
                                NavigationLink(value: Route.dump(dump.id)) {
                                    cell(photo.source, aspect: photo.aspectRatio)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(photo.altText ?? "Photo")
                            }
                        }
                        ForEach(week.tagged) { tagged in
                            NavigationLink(value: Route.dump(tagged.photo.dumpID)) {
                                cell(tagged.photo.source, aspect: tagged.photo.aspectRatio)
                                    .overlay(alignment: .bottomLeading) { AttributionChip(user: tagged.from) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Photo from \(tagged.from.firstName)'s week")
                            .contextMenu {
                                if isOwn {
                                    Button("Remove from my week", systemImage: Icon.trash, role: .destructive) {
                                        onRemoveTagged(tagged)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .scrollIndicators(.hidden)
                .frame(height: Theme.rowHeight)
            }
        }
    }

    private func cell(_ source: PhotoSource, aspect: CGFloat) -> some View {
        PhotoView(source: source)
            .frame(width: Theme.rowHeight * min(max(aspect, 0.6), 1.8), height: Theme.rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .hoverEffect(.lift)
    }
}
