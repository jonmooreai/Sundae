import SwiftUI
import UIKit

enum ComposeStep: Hashable {
    case pick, arrange, caption, posted
}

/// The full-screen posting flow: greet (on Sunday open), pick, arrange and tag, caption, posted.
/// Presented over the tab shell. The draft lives in `ComposeStore`, so closing keeps it.
struct ComposeFlow: View {
    @Environment(AppModel.self) private var model
    @State private var path: [ComposeStep] = []
    @State private var library = PhotoLibrary()

    private var compose: ComposeStore { model.compose }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .swipeBackEnabled()
                .navigationDestination(for: ComposeStep.self) { step in
                    Group {
                        switch step {
                        case .pick: PickPhotosStep(library: library, path: $path)
                        case .arrange: ArrangeStep(library: library, path: $path)
                        case .caption: CaptionStep(path: $path)
                        case .posted: PostedStep(path: $path)
                        }
                    }
                    // Once the week is up there is nothing to go back to.
                    .swipeBackEnabled(step != .posted)
                }
        }
        .filmGrain()
        .task {
            await compose.load(weekStart: model.currentWeekStart)
            library.refreshStatus()
        }
    }

    @ViewBuilder
    private var root: some View {
        switch compose.entry {
        case .prompt: SundayPromptStep(library: library, path: $path)
        case .pick: PickPhotosStep(library: library, path: $path)
        case .arrange: ArrangeStep(library: library, path: $path)
        }
    }
}

// MARK: - Shared pieces

/// A handful of sprinkles that scatter from the check when the week goes up.
struct Sprinkles: View {
    let fired: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let colors: [Color] = [Theme.cherry, Color.accentColor, Color(red: 0.93, green: 0.76, blue: 0.40), Color(red: 0.62, green: 0.74, blue: 0.86)]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { i in
                let angle = Double(i) * 20 + Double(i % 3) * 7
                let distance = fired ? 86.0 + Double(i % 4) * 16 : 10
                Capsule()
                    .fill(colors[i % colors.count])
                    .frame(width: 5, height: 13)
                    .rotationEffect(.degrees(angle + (fired ? 140 : 0)))
                    .offset(x: cos(angle * .pi / 180) * distance, y: sin(angle * .pi / 180) * distance)
                    .opacity(fired ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.15 + Double(i % 5) * 0.03), value: fired)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Top of a flow step: back or close on the left, a serif title, chrome on the right.
struct FlowHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var isRoot: Bool
    var onClose: () -> Void
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isRoot {
                IconButton(glyph: Glyph.close, label: "Close", size: 22, action: onClose)
                    .padding(.leading, -8)
            } else {
                IconButton(glyph: Glyph.back, label: "Back", size: 24) { dismiss() }
                    .padding(.leading, -8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.display(24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

/// Bottom bar with a count on the left and the one primary action on the right.
struct FlowBottomBar<Leading: View>: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void
    let leading: () -> Leading

    init(title: String, isEnabled: Bool = true, isLoading: Bool = false,
         action: @escaping () -> Void, @ViewBuilder leading: @escaping () -> Leading) {
        self.title = title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.action = action
        self.leading = leading
    }

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 0)
            Button(action: action) {
                ZStack {
                    Text(title).opacity(isLoading ? 0 : 1)
                    if isLoading { ProgressView().tint(.white) }
                }
                .frame(minWidth: 80)
            }
            .buttonStyle(.pill(.primary))
            .disabled(!isEnabled || isLoading)
            .accessibilityIdentifier("flow-primary")
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
        .background {
            Theme.background
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Small thumbnails of the draft, used on the caption and posted steps.
struct DraftThumbnailStrip: View {
    let photos: [DraftPhoto]
    var side: CGFloat = 56
    /// Centered in the available width when the strip fits; scrolls from the left when it does not.
    var centered = false

    private var contentWidth: CGFloat {
        CGFloat(photos.count) * side + CGFloat(max(photos.count - 1, 0)) * 6 + Theme.pagePadding * 2
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(photos) { photo in
                    PhotoView(source: photo.source)
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.2, style: .continuous))
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
                centered ? max(length, contentWidth) : contentWidth
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// Three real photos from the week, fanned like prints on a table.
struct FannedPhotos: View {
    let images: [UIImage]

    var body: some View {
        ZStack {
            ForEach(Array(images.prefix(3).enumerated()), id: \.offset) { index, image in
                let angle: Double = [-9, 7, -2][index % 3]
                let offset: CGFloat = [-34, 34, 0][index % 3]
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                    .rotationEffect(.degrees(angle))
                    .offset(x: offset, y: CGFloat(index) * -4)
            }
        }
        .frame(height: 220)
        .accessibilityHidden(true)
    }
}

// MARK: - Sunday prompt

/// The first thing you see on Sunday: a greeting and one button.
struct SundayPromptStep: View {
    @Environment(AppModel.self) private var model
    let library: PhotoLibrary
    @Binding var path: [ComposeStep]
    @State private var previews: [UIImage] = []
    @State private var preparing = false

    private var compose: ComposeStore { model.compose }
    /// Photos kept with this week's saved ideas, ready to start the post.
    private var savedPhotos: [SavedPhotoForPost] { model.savedIdeas.photosForPost() }
    private var startsFromSaved: Bool { !compose.hasPosted && compose.draft.isEmpty && !savedPhotos.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CherryMark(size: 30)
                Spacer()
                Button("Not now") { notNow() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 18) {
                Text(dateLine)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Text(compose.hasPosted ? "It's Sunday.\nYour week is up." : "It's Sunday.\nPost your week.")
                    .font(Theme.display(44))
                    .lineSpacing(2)
                Text(compose.hasPosted
                     ? "Add a photo, fix the caption, or tag someone you missed. You have until midnight."
                     : startsFromSaved ? savedLine
                     : "Pick the photos, tag who was there, and say how it went. You have until midnight.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 20)

            Group {
                if previews.isEmpty {
                    PhotoStackIcon(size: 96)
                } else {
                    FannedPhotos(images: previews)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 20)

            PrimaryButton(title: compose.hasPosted ? "Edit your week" : startsFromSaved ? "Start with your saved photos" : "Pick your photos",
                          isLoading: preparing) {
                Haptics.light()
                if compose.hasPosted {
                    compose.entry = .arrange
                    path = []
                } else if startsFromSaved {
                    Task { await startFromSaved() }
                } else {
                    path.append(.pick)
                }
            }
            Button(compose.hasPosted ? "See the feed" : "Show me the feed first") { notNow() }
                .buttonStyle(.pill(.quiet, fullWidth: true))
                .padding(.top, 4)
        }
        .padding(24)
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPreviews() }
    }

    private var dateLine: String {
        model.clock.now().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var savedLine: String {
        let count = savedPhotos.count
        let photos = count == 1 ? "1 photo" : "\(count) photos"
        return "Your saved ideas start it with \(photos). Add more, tag who was there, and say how it went. You have until midnight."
    }

    /// Fills the draft from saved ideas and opens it ready to arrange. If none of their photos
    /// could be read (Photos access taken away, photos deleted), the grid instead.
    private func startFromSaved() async {
        preparing = true
        await compose.startFromSaved(savedPhotos, library: library)
        preparing = false
        path.append(compose.draft.isEmpty ? .pick : .arrange)
    }

    private func notNow() {
        compose.dismissPrompt(for: model.currentWeekStart)
        compose.dismiss()
    }

    /// Real photos from this week when the library is already allowed, saved ideas' first.
    /// Never asks here.
    private func loadPreviews() async {
        guard library.isAuthorized else { return }
        library.loadAssets(from: model.currentWeekStart, to: model.clock.weekEnd(containing: model.currentWeekStart))
        let saved = PhotoFinder.assets(savedPhotos.map(\.assetID))
        let fromSaved = savedPhotos.compactMap { saved[$0.assetID] }
        let picks = fromSaved.isEmpty ? Array(library.assets.suffix(3)) : Array(fromSaved.prefix(3))
        var images: [UIImage] = []
        for asset in picks {
            if let image = await library.thumbnail(for: asset, side: 300) { images.append(image) }
        }
        previews = images
    }
}

// MARK: - Posted

struct PostedStep: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [ComposeStep]
    @State private var appeared = false

    private var compose: ComposeStore { model.compose }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Icon(Glyph.approvals, weight: .fill, size: 84)
                .foregroundStyle(Color.accentColor)
                .scaleEffect(appeared ? 1 : 0.6)
                .animation(.bouncy(duration: 0.5), value: appeared)
                .background { Sprinkles(fired: appeared) }
            Text(compose.queuedOffline ? "Saved for when you're back online." : "Your week is up.")
                .font(Theme.display(36))
                .multilineTextAlignment(.center)
            Text(compose.queuedOffline
                 ? "It posts the moment the network returns, as long as it is still Sunday."
                 : "Edit any time until midnight. Tagged friends get a request to approve.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            DraftThumbnailStrip(photos: compose.draft.photos, side: 64, centered: true)
                .padding(.top, 8)
            Spacer()
            PrimaryButton(title: "See the feed") {
                compose.dismiss()
                model.requestedTab = .feed
            }
            Button("Edit") {
                compose.entry = .arrange
                path = []
            }
            .buttonStyle(.pill(.quiet, fullWidth: true))
            .padding(.top, 2)
        }
        .padding(24)
        .background(Theme.background)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { appeared = true }
    }
}
