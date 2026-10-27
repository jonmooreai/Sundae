import Photos
import SwiftUI

/// Search the people you follow or who follow you, attach up to 10 to one photo.
struct TagPickerSheet: View {
    let photo: DraftPhoto
    let users: [User]
    let onSave: ([User]) -> Void

    @Environment(AppModel.self) private var model
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
                                UserRow(user: user, subtitle: MomentMemory.birthday(user.birthday, fallsInWeekStarting: model.currentWeekStart, calendar: model.clock.calendar) ? "Birthday this week" : nil)
                                ZStack {
                                    Circle().strokeBorder(isOn ? Color.accentColor : Theme.hairline, lineWidth: 1.5)
                                    if isOn {
                                        Circle().fill(Color.accentColor)
                                        Icon(Glyph.done, weight: .bold, size: 14).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 26, height: 26)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.textButtonTint() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(selected)
                        dismiss()
                    }
                    .textButtonTint()
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
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.textButtonTint() }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.textButtonTint() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .textButtonTint()
                }
            }
            .onAppear { text = photo.altText }
        }
        .presentationDetents([.medium, .large])
    }
}
