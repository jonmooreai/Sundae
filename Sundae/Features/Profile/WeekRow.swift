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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isCurrent ? "This week" : model.clock.rangeLabel(weekStart: week.weekStart))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                if isCurrent {
                    Text(model.clock.rangeLabel(weekStart: week.weekStart))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isOwn, isCurrent, week.dump == nil, model.isSunday {
                    Text("Not posted yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            if isOwn, isCurrent, let caption = week.dump?.caption, !caption.isEmpty {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.pagePadding)
            }

            if week.isEmpty, isOwn, isCurrent {
                postCard.padding(.horizontal, Theme.pagePadding)
            } else if week.isEmpty {
                Text("No photos this week.")
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
                                    .overlay(alignment: .bottomLeading) { AttributionChip(user: tagged.from).padding(4) }
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
                .scrollClipDisabled()
                .frame(height: Theme.rowHeight)
            }
        }
    }

    /// Square rounded cards, inset from the edge so they read as a shelf of prints.
    private func cell(_ source: PhotoSource, aspect: CGFloat) -> some View {
        PhotoView(source: source)
            .frame(width: Theme.rowHeight, height: Theme.rowHeight)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
            .hoverEffect(.lift)
    }

    /// A dashed, empty card for this week. Tapping it opens the Post tab.
    private var postCard: some View {
        Button {
            Haptics.light()
            model.requestedTab = .post
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    .foregroundStyle(.tertiary)
                VStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                    Text("Post your week")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: Theme.rowHeight, height: Theme.rowHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post your week")
    }
}
