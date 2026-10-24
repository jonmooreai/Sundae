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
                postInvite.padding(.horizontal, Theme.pagePadding)
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
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .scrollTargetBehavior(.viewAligned)
                .frame(height: isCurrent ? nil : Theme.rowHeight)
            }
        }
    }

    /// Rounded square cards. This week's are nearly full width, with the next one peeking in;
    /// older weeks are a smaller shelf of prints.
    @ViewBuilder
    private func cell(_ source: PhotoSource, aspect: CGFloat) -> some View {
        if isCurrent {
            PhotoView(source: source)
                .aspectRatio(1, contentMode: .fit)
                .containerRelativeFrame(.horizontal, count: 6, span: 5, spacing: Theme.gap)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius + 4, style: .continuous))
                .hoverEffect(.lift)
        } else {
            PhotoView(source: source)
                .frame(width: Theme.rowHeight, height: Theme.rowHeight)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
                .hoverEffect(.lift)
        }
    }

    /// This week, before you post: one card that opens the posting flow.
    private var postInvite: some View {
        Button {
            Haptics.light()
            model.compose.present(.pick)
        } label: {
            HStack(spacing: 16) {
                PhotoStackIcon(size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Post your week")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Pick the photos from \(model.clock.rangeLabel(weekStart: week.weekStart)).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: Icon.chevronRight)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post your week")
    }
}
