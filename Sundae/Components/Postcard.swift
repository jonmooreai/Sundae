import SwiftUI
import UIKit

/// Loads the pixels behind a `PhotoSource`, so a view can be rendered to an image in one go.
@MainActor
enum PhotoLoader {
    static func uiImage(for source: PhotoSource) async -> UIImage? {
        switch source {
        case .data(let data):
            return await ImageCache.image(for: data)
        case .remote(let url):
            guard let result = try? await URLSession.shared.data(from: url) else { return nil }
            return await ImageCache.image(for: result.0)
        case .placeholder:
            return nil
        }
    }
}

/// A photo ready for a postcard: pixels when they loaded, a seed for the soft stand-in otherwise.
struct PostcardPhoto {
    let image: UIImage?
    let seed: Int

    /// Fills the box and is clipped to it, so a tall photo never spills over the card.
    func view(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                PlaceholderPhoto(seed: seed)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// One week on cream paper: the dates, up to three photos, what you did, and the mark.
/// Made to be sent to a group chat.
struct WeekPostcard: View {
    static let size = CGSize(width: 900, height: 1200)

    let title: String
    let subtitle: String
    let photos: [PostcardPhoto]
    let line: String?

    var body: some View {
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(title).font(Theme.display(64)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(subtitle).font(.system(size: 30, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                collage
                Spacer(minLength: 0)
                if let line, !line.isEmpty {
                    Text(line)
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    SundaeMark(size: 56, lineWidth: 1.2)
                    Text("Sundae").font(Theme.display(36))
                    Text("Sundays only.").font(.system(size: 28)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }

    /// One photo fills; two stand side by side; three make a big one over two small ones.
    @ViewBuilder
    private var collage: some View {
        let width: CGFloat = Self.size.width - 128
        let gap: CGFloat = 16
        let radius: CGFloat = 28
        switch photos.count {
        case 0:
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.surface).frame(width: width, height: 700)
        case 1:
            photos[0].view(width: width, height: 760, cornerRadius: radius)
        case 2:
            HStack(spacing: gap) {
                photos[0].view(width: (width - gap) / 2, height: 640, cornerRadius: radius)
                photos[1].view(width: (width - gap) / 2, height: 640, cornerRadius: radius)
            }
        default:
            VStack(spacing: gap) {
                photos[0].view(width: width, height: 500, cornerRadius: radius)
                HStack(spacing: gap) {
                    photos[1].view(width: (width - gap) / 2, height: 300, cornerRadius: radius)
                    photos[2].view(width: (width - gap) / 2, height: 300, cornerRadius: radius)
                }
            }
        }
    }
}

/// A year of Sundays as small squares, oldest first, empty weeks left cream. A poster by December.
struct YearPoster: View {
    static let size = CGSize(width: 900, height: 1200)
    static let columns = 8

    let title: String
    let subtitle: String
    let cells: [PostcardPhoto?]

    var body: some View {
        let width: CGFloat = Self.size.width - 128
        let gap: CGFloat = 12
        let side = (width - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        ZStack {
            Theme.background
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(Theme.display(64))
                    Text(subtitle).font(.system(size: 30)).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: Self.columns), spacing: gap) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        if let cell {
                            cell.view(width: side, height: side, cornerRadius: 12)
                        } else {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.surface)
                                .frame(width: side, height: side)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    SundaeMark(size: 56, lineWidth: 1.2)
                    Text("Sundae").font(Theme.display(36))
                    Text("\(cells.compactMap { $0 }.count) of \(cells.count) Sundays").font(.system(size: 28)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(64)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }
}

/// Draws a postcard-sized view into pixels, twice the size for sharp sharing.
@MainActor
enum Postcards {
    static func image<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }

    /// The first three photos of a week, loaded, then drawn.
    static func render(dump: Dump, clock: SundayClock, line: String?) async -> UIImage? {
        var photos: [PostcardPhoto] = []
        for photo in dump.photos.sorted(by: { $0.order < $1.order }).prefix(3) {
            let image = await PhotoLoader.uiImage(for: photo.source)
            photos.append(PostcardPhoto(image: image, seed: photo.id.hashValue))
        }
        let card = WeekPostcard(title: clock.rangeLabel(weekStart: dump.weekStart),
                                subtitle: "\(dump.author.firstName)'s week",
                                photos: photos, line: line)
        return image(card, size: WeekPostcard.size)
    }

    /// Fifty-two weeks ending with the current one, each with its first photo if there was one.
    static func renderYear(profile: Profile, clock: SundayClock) async -> UIImage? {
        let starts = clock.recentWeekStarts(count: 52).reversed()
        var cells: [PostcardPhoto?] = []
        for start in starts {
            if let week = profile.weeks.first(where: { $0.weekStart == start }),
               let photo = week.dump?.photos.min(by: { $0.order < $1.order }) {
                let image = await PhotoLoader.uiImage(for: photo.source)
                cells.append(PostcardPhoto(image: image, seed: photo.id.hashValue))
            } else {
                cells.append(nil)
            }
        }
        let poster = YearPoster(title: "A year of Sundays", subtitle: "\(profile.user.displayName), the last 52 weeks", cells: cells)
        return image(poster, size: YearPoster.size)
    }
}

/// Renders once, then hands the share sheet an image. Quiet until the picture is ready.
struct PostcardShareButton: View {
    @Environment(AppModel.self) private var model
    let dump: Dump
    var line: String? = nil
    var kind: PillButtonStyle.Kind = .quiet
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("\(dump.author.firstName)'s week on Sundae", image: Image(uiImage: image))) {
                    HStack(spacing: 8) {
                        Icon(Glyph.share, size: 18)
                        Text("Share a postcard")
                    }
                }
                .buttonStyle(.pill(kind, fullWidth: true))
            } else {
                Button {} label: {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Making your postcard")
                    }
                }
                .buttonStyle(.pill(kind, fullWidth: true))
                .disabled(true)
            }
        }
        .task(id: dump.id) {
            image = await Postcards.render(dump: dump, clock: model.clock, line: line)
        }
    }
}

/// The postcard as one quiet icon in a post's action row. Dim until the picture is ready.
struct PostcardShareIcon: View {
    @Environment(AppModel.self) private var model
    let dump: Dump
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("\(dump.author.firstName)'s week on Sundae", image: Image(uiImage: image))) {
                    Icon(Glyph.share, size: 24).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            } else {
                Icon(Glyph.share, size: 24).foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel("Share a postcard")
        .task(id: dump.id) {
            image = await Postcards.render(dump: dump, clock: model.clock, line: dump.caption.isEmpty ? nil : dump.caption)
        }
    }
}

/// The year poster as a share sheet, rendered on tap so the profile stays quick.
struct YearShareButton: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    @State private var image: UIImage?
    @State private var isRendering = false

    var body: some View {
        if let image {
            ShareLink(item: Image(uiImage: image),
                      preview: SharePreview("A year of Sundays", image: Image(uiImage: image))) {
                Icon(Glyph.share, size: 18)
            }
            .buttonStyle(.pill(.quiet, size: .small))
            .accessibilityLabel("Share the year")
        } else {
            Button {
                guard !isRendering else { return }
                isRendering = true
                Task {
                    image = await Postcards.renderYear(profile: profile, clock: model.clock)
                    isRendering = false
                }
            } label: {
                if isRendering {
                    ProgressView().controlSize(.small)
                } else {
                    Icon(Glyph.share, size: 18)
                }
            }
            .buttonStyle(.pill(.quiet, size: .small))
            .accessibilityLabel("Share the year")
        }
    }
}
