import Photos
import PhotosUI
import SwiftUI
import PhosphorSwift

/// Step one: a grid of this week's photos, tap to pick up to 15, in the order you tap.
/// The Photos picker is always one tap away for anything the grid cannot show.
struct PickPhotosStep: View {
    @Environment(AppModel.self) private var model
    let library: PhotoLibrary
    @Binding var path: [ComposeStep]

    private enum Scope: Hashable {
        case week, all
    }

    @State private var scope: Scope = .week
    @State private var selected: [String] = []
    @State private var assetsByID: [String: PHAsset] = [:]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isPreparing = false

    private var compose: ComposeStore { model.compose }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 2), count: 3) }
    private var total: Int { selected.count + compose.nonLibraryPhotoCount }
    private var remaining: Int { max(0, DumpDraft.maxPhotos - total) }

    var body: some View {
        VStack(spacing: 0) {
            FlowHeader(title: "Pick your photos", subtitle: model.clock.rangeLabel(weekStart: model.currentWeekStart),
                       isRoot: path.isEmpty, onClose: { compose.dismiss() }) {
                if library.isAuthorized {
                    ChipPicker(options: [(Scope.week, "This week"), (Scope.all, "All")], selection: $scope)
                }
            }
            if library.isAuthorized {
                grid
            } else {
                permission
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if library.isAuthorized {
                FlowBottomBar(title: "Next", isEnabled: total > 0, isLoading: isPreparing) {
                    Task { await next() }
                } leading: {
                    Text(total == 0 ? "Pick up to \(DumpDraft.maxPhotos)" : "\(total) of \(DumpDraft.maxPhotos)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .overlay {
            if isPreparing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing \(selected.count == 1 ? "your photo" : "\(selected.count) photos")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        }
        .task {
            library.refreshStatus()
            selected = compose.libraryAssetIDsInOrder
            reload()
        }
        .onChange(of: scope) { _, _ in reload() }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await compose.importPickerItems(items)
                pickerItems = []
            }
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            VStack(spacing: 10) {
                if library.assets.isEmpty {
                    VStack(spacing: 12) {
                        Text(scope == .week ? "No photos from this week yet." : "No photos in your library.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if scope == .week {
                            Button("Show all photos") { scope = .all }
                                .buttonStyle(.pill(.secondary, size: .small))
                        }
                    }
                    .padding(.vertical, 48)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(library.assets, id: \.localIdentifier) { asset in
                            cell(asset)
                        }
                    }
                }

                PhotosPicker(selection: $pickerItems, maxSelectionCount: remaining, selectionBehavior: .ordered,
                             matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        Icon(Glyph.photos, size: 18)
                        Text("Choose from another album")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.pill(.quiet))
                .disabled(remaining == 0)
                .padding(.vertical, 12)
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
                        Circle()
                            .fill(index == nil ? Color.black.opacity(0.25) : Color.accentColor)
                        Circle()
                            .strokeBorder(.white, lineWidth: 1.5)
                        if let index {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .padding(6)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-cell")
        .accessibilityLabel(index.map { "Selected, number \($0 + 1)" } ?? "Photo")
    }

    // MARK: - Permission

    private var permission: some View {
        VStack(spacing: 20) {
            Spacer()
            PhotoStackIcon(size: 72)
            Text("Show this week's photos")
                .font(.title2.weight(.semibold))
            Text(library.canAsk
                 ? "Sundae reads your library to put Monday onward first. Nothing leaves your phone until you post it."
                 : "Photo access is off. Turn it on in Settings, or choose from Photos instead.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer()
            if library.canAsk {
                PrimaryButton(title: "Show my photos") {
                    Task {
                        await library.requestAccess()
                        reload()
                    }
                }
            } else {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Text("Open Settings")
                }
                .buttonStyle(.pill(.primary, fullWidth: true))
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: remaining, selectionBehavior: .ordered,
                         matching: .images, photoLibrary: .shared()) {
                Text("Choose from Photos instead")
            }
            .buttonStyle(.pill(.quiet, fullWidth: true))
        }
        .padding(24)
    }

    // MARK: - Actions

    private func reload() {
        guard library.isAuthorized else { return }
        switch scope {
        case .week:
            library.loadAssets(from: model.currentWeekStart, to: model.clock.weekEnd(containing: model.currentWeekStart))
        case .all:
            library.loadAllAssets()
        }
        for asset in library.assets { assetsByID[asset.localIdentifier] = asset }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if remaining > 0 {
            selected.append(id)
            Haptics.light()
        }
    }

    /// Re-encodes what you picked, drops what you unpicked, puts the week in order, and moves on.
    private func next() async {
        isPreparing = true
        for assetID in compose.libraryPhotoIDs.keys where !selected.contains(assetID) {
            compose.removeLibraryAsset(assetID)
        }
        for assetID in selected where compose.libraryPhotoIDs[assetID] == nil {
            guard let asset = assetsByID[assetID], let data = await library.imageData(for: asset) else { continue }
            await compose.importLibraryData(data, assetID: assetID, takenAt: asset.creationDate)
        }
        compose.sortChronologically()
        isPreparing = false
        advance()
    }

    /// Back to the arrange step when it is already in the chain, otherwise forward to it.
    private func advance() {
        if compose.entry == .arrange, path == [.pick] {
            path.removeLast()
        } else if path.count >= 2, path[path.count - 2] == .arrange {
            path.removeLast()
        } else {
            path.append(.arrange)
        }
    }
}

/// One camera roll thumbnail, loaded on demand.
struct LibraryThumbnail: View {
    let library: PhotoLibrary
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                image = await library.thumbnail(for: asset, side: 160)
            }
    }
}
