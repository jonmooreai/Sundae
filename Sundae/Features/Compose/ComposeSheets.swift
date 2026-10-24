import Photos
import SwiftUI

/// Search the people you follow or who follow you, attach up to 10 to one photo.
struct TagPickerSheet: View {
    let photo: DraftPhoto
    let users: [User]
    let onSave: ([User]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [User] = []
    @State private var query = ""

    private var results: [User] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return users }
        return users.filter { $0.username.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotoView(source: photo.source)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    if users.isEmpty {
                        Text("You can tag people you follow or who follow you. Find your friends in Search first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { user in
                        let isOn = selected.contains { $0.id == user.id }
                        Button {
                            if isOn {
                                selected.removeAll { $0.id == user.id }
                            } else if selected.count < DumpDraft.maxTagsPerPhoto {
                                selected.append(user)
                            }
                        } label: {
                            HStack {
                                UserRow(user: user)
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                                    .font(.title3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(selected.isEmpty ? "Who was there?" : "\(selected.count) of \(DumpDraft.maxTagsPerPhoto) tagged")
                }
            }
            .searchable(text: $query, prompt: "Name or username")
            .navigationTitle("Tag friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(selected)
                        dismiss()
                    }
                }
            }
            .onAppear { selected = photo.taggedUsers }
        }
    }
}

/// Drag to reorder. Default order is chronological; this is for the rest.
struct ReorderSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.compose.draft.photos) { photo in
                    HStack(spacing: 12) {
                        PhotoView(source: photo.source)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        if photo.taggedUsers.isEmpty {
                            Text("No tags").foregroundStyle(.secondary)
                        } else {
                            Text("with " + ListFormatter.localizedString(byJoining: photo.taggedUsers.map(\.firstName)))
                        }
                    }
                }
                .onMove { from, to in model.compose.move(from: from, to: to) }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Per-photo alt text for VoiceOver. Optional, short, plain.
struct AltTextSheet: View {
    let photo: DraftPhoto
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                PhotoView(source: photo.source)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                TextField("Describe the photo for people who can't see it", text: $text, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                Spacer()
            }
            .padding(Theme.pagePadding)
            .navigationTitle("Alt text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
            .onAppear { text = photo.altText }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Thumbnails from the camera roll for the current week (or one day), tap to add.
struct WeekLibraryGrid: View {
    let library: PhotoLibrary
    let columns: [GridItem]
    let onPick: (PHAsset) -> Void

    var body: some View {
        if library.assets.isEmpty {
            Text("No photos in this range yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: columns, spacing: Theme.gap) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    Button { onPick(asset) } label: {
                        LibraryThumbnail(library: library, asset: asset)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add photo from \(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "library")")
                }
            }
        }
    }
}

private struct LibraryThumbnail: View {
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
