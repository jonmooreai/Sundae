import Photos
import SwiftUI
import PhosphorSwift

/// The ideas saved this week and the photos set aside for them. On Sunday they start the post.
/// Until then, all of it stays on this phone.
struct YourWeekView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var library = PhotoLibrary()
    /// The saved photos still in the library, by id, for their thumbnails.
    @State private var assets: [String: PHAsset] = [:]
    @State private var picking: SavedIdea?

    private var saved: SavedIdeasStore { model.savedIdeas }
    private var photoIDs: [String] { saved.ideas.flatMap { $0.photos.map(\.assetID) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ideas you saved, with their photos. On Sunday they start your post. Until then they stay on this phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    if !library.isAuthorized { access }
                    if saved.ideas.isEmpty {
                        empty
                    } else {
                        ForEach(saved.ideas) { idea in
                            SavedIdeaCard(idea: idea, assets: assets, library: library,
                                          canAddPhotos: library.isAuthorized || library.canAsk,
                                          caption: captionBinding(for: idea.id),
                                          onAdd: { picking = idea },
                                          onRemovePhoto: { saved.removePhoto($0, from: idea.id) },
                                          onRemove: { saved.remove(idea.id) })
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 32)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: saved.ideas)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.background)
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .task {
            library.refreshStatus()
            await saved.findPhotos(clock: model.clock)
            loadAssets()
        }
        .onChange(of: photoIDs) { _, _ in loadAssets() }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings, maybe with Photos turned on.
            guard phase == .active else { return }
            library.refreshStatus()
            Task {
                await saved.findPhotos(clock: model.clock)
                loadAssets()
            }
        }
        .sheet(item: $picking) { idea in
            IdeaPhotoPicker(idea: idea, library: library)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Your week")
                    .font(Theme.display(28))
                Text(model.clock.rangeLabel(weekStart: model.currentWeekStart))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            IconButton(glyph: Glyph.close, label: "Close", size: 22, filled: true) { dismiss() }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// Asked here only when someone came to add photos; Save asks once on its own.
    @ViewBuilder
    private var access: some View {
        VStack(alignment: .leading, spacing: 12) {
            if library.canAsk {
                Text("Let Sundae find the photos you take at the places you saved. It looks at where this week's photos were taken, on this phone.")
                    .font(.subheadline)
                Button("Allow photo access") {
                    Task {
                        saved.askedForPhotos = true
                        await library.requestAccess()
                        await saved.findPhotos(clock: model.clock)
                        loadAssets()
                    }
                }
                .buttonStyle(.pill(.primary, size: .small))
            } else {
                Text("Photo access is off for Sundae, so photos can't be found or added here.")
                    .font(.subheadline)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iOS Settings", destination: url)
                        .buttonStyle(.pill(.secondary, size: .small))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Icon(Glyph.saved, size: 40)
                .foregroundStyle(Color.accentColor)
            Text("Nothing saved yet")
                .font(.title3.weight(.semibold))
            Text("Tap Save on an idea you like. It waits here for the week, and on Sunday its photos start your post.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 16)
    }

    private func captionBinding(for id: String) -> Binding<String> {
        Binding(get: { saved.ideas.first { $0.id == id }?.caption ?? "" },
                set: { saved.setCaption($0, for: id) })
    }

    private func loadAssets() {
        guard library.isAuthorized else { return }
        assets = PhotoFinder.assets(photoIDs)
    }
}

/// One saved idea: what it was, where, its photos, and the caption they share.
private struct SavedIdeaCard: View {
    let idea: SavedIdea
    let assets: [String: PHAsset]
    let library: PhotoLibrary
    let canAddPhotos: Bool
    @Binding var caption: String
    let onAdd: () -> Void
    let onRemovePhoto: (String) -> Void
    let onRemove: () -> Void

    private let side: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(idea.suggestion.text)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Menu {
                    Button(role: .destructive, action: onRemove) {
                        Text("Remove from your week")
                    }
                } label: {
                    Icon(Glyph.more, weight: .bold, size: 20)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for this idea")
                .padding(.top, -10)
                .padding(.trailing, -10)
            }

            if !idea.photos.isEmpty || canAddPhotos {
                photos
            }

            if idea.photos.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Caption for these photos (optional)", text: $caption, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                    .accessibilityLabel("Caption for this idea's photos")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var photos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(idea.photos) { photo in
                    thumbnail(photo)
                }
                if idea.canAddMore, canAddPhotos {
                    Button(action: onAdd) {
                        VStack(spacing: 4) {
                            Icon(Glyph.plus, weight: .bold, size: 18)
                            Text(idea.photos.isEmpty ? "Add photos" : "Add")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(width: idea.photos.isEmpty ? side * 1.5 : side, height: side)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add photos to this idea")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func thumbnail(_ photo: SavedPhoto) -> some View {
        Group {
            if let asset = assets[photo.assetID] {
                LibraryThumbnail(library: library, asset: asset)
            } else {
                Rectangle().fill(Theme.fill)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                onRemovePhoto(photo.assetID)
            } label: {
                Icon(Glyph.close, weight: .bold, size: 10)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.black.opacity(0.45), in: Circle())
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take this photo off the idea")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(photo.takenAt.map { "Photo from \($0.formatted(.dateTime.weekday(.wide).hour().minute()))" } ?? "Photo")
    }

    /// "Juniper Bakery, saved Tuesday".
    private var detail: String {
        let day = "saved \(idea.savedAt.formatted(.dateTime.weekday(.wide)))"
        guard let place = idea.suggestion.place?.name else { return day.prefix(1).uppercased() + String(day.dropFirst()) }
        return "\(place), \(day)"
    }

    private var hint: String {
        if idea.coordinate != nil, PhotoFinder.isAuthorized {
            return "Photos you take there show up here on their own."
        }
        return "Add photos from this week once you've done it."
    }
}

/// This week's photos, newest first, to pick up to six for one idea.
struct IdeaPhotoPicker: View {
    let idea: SavedIdea
    let library: PhotoLibrary
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []
    @State private var dates: [String: Date] = [:]

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 2), count: 3) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add photos")
                        .font(Theme.display(24))
                    Text(idea.suggestion.place?.name ?? idea.suggestion.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                IconButton(glyph: Glyph.close, label: "Cancel", size: 22, filled: true) { dismiss() }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if library.isAuthorized {
                grid
            } else {
                permission
            }
        }
        .background(Theme.background)
        .presentationBackground(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if library.isAuthorized {
                FlowBottomBar(title: "Done") {
                    finish()
                } leading: {
                    Text("\(selected.count) of \(SavedIdea.maxPhotos)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .task {
            selected = idea.photos.map(\.assetID)
            for photo in idea.photos { dates[photo.assetID] = photo.takenAt }
            library.refreshStatus()
            reload()
        }
    }

    private var grid: some View {
        ScrollView {
            if library.assets.isEmpty {
                Text("No photos from this week yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 48)
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(library.assets.reversed()), id: \.localIdentifier) { asset in
                        cell(asset)
                    }
                }
            }
        }
    }

    private func cell(_ asset: PHAsset) -> some View {
        let index = selected.firstIndex(of: asset.localIdentifier)
        return Button {
            toggle(asset)
        } label: {
            LibraryThumbnail(library: library, asset: asset)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if index != nil {
                        Rectangle().strokeBorder(Color.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(index == nil ? Color.black.opacity(0.25) : Color.accentColor)
                        Circle().strokeBorder(.white, lineWidth: 1.5)
                        if index != nil {
                            Icon(Glyph.done, weight: .bold, size: 12)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index == nil ? "Photo" : "Photo, selected")
    }

    private var permission: some View {
        VStack(spacing: 16) {
            Spacer()
            PhotoStackIcon(size: 72)
            Text(library.canAsk
                 ? "Sundae shows this week's photos here so you can pick the ones for this idea. They stay on your phone until you post on Sunday."
                 : "Photo access is off for Sundae. Turn it on in iOS Settings to add photos here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            if library.canAsk {
                PrimaryButton(title: "Show my photos") {
                    Task {
                        model.savedIdeas.askedForPhotos = true
                        await library.requestAccess()
                        reload()
                    }
                }
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: url) { Text("Open iOS Settings") }
                    .buttonStyle(.pill(.primary, fullWidth: true))
            }
        }
        .padding(24)
    }

    private func reload() {
        guard library.isAuthorized else { return }
        library.loadAssets(from: model.currentWeekStart, to: model.clock.weekEnd(containing: model.currentWeekStart))
        for asset in library.assets { dates[asset.localIdentifier] = asset.creationDate }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if selected.count < SavedIdea.maxPhotos {
            selected.append(id)
            Haptics.light()
        }
    }

    private func finish() {
        let photos = selected.map { id in
            SavedPhoto(assetID: id, takenAt: dates[id],
                       found: idea.photos.first { $0.assetID == id }?.found ?? false)
        }
        model.savedIdeas.setPhotos(photos, for: idea.id, at: model.clock.now())
        dismiss()
    }
}

/// Asked once, the first time an idea is saved: may Sundae find its photos by place?
struct PhotoAccessSheet: View {
    let onAnswered: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ConsentSheet(
            title: "Find the photos for ideas you save?",
            points: [
                .init(glyph: Glyph.pin,
                      text: "When you take photos at a place you saved, Sundae finds them by where they were taken and keeps them with the idea for Sunday."),
                .init(glyph: Glyph.lock,
                      text: "It all happens on this phone. Your photos and where they were taken stay here; only the ones you post on Sunday leave it."),
                .init(glyph: Glyph.photos,
                      text: "You can add photos to any saved idea yourself too. iOS asks next."),
            ],
            agreeTitle: "Allow photo access"
        ) {
            Task {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                onAnswered()
            }
        }
        .onAppear { model.savedIdeas.askedForPhotos = true }
    }
}
