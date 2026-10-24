import PhotosUI
import SwiftUI

/// Pick, order, tag, caption, post. One dump per week, editable until midnight.
/// Regular width puts the photo grid beside the caption instead of above it.
struct ComposeScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var taggingPhoto: DraftPhoto?
    @State private var altPhoto: DraftPhoto?
    @State private var showReorder = false
    @State private var confirmDelete = false
    @State private var library = PhotoLibrary()
    @State private var libraryDay: Date?
    @State private var showLibrary = true

    private var compose: ComposeStore { model.compose }
    private var weekStart: Date { model.currentWeekStart }

    var body: some View {
        NavigationStack {
            Group {
                if compose.isLocked {
                    ContentUnavailableView("This week is locked", systemImage: Icon.lock,
                                           description: Text("Sunday's over. Your week stays as it was posted."))
                } else if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 28) {
                        ScrollView { photoColumn.padding(.vertical) }
                        ScrollView { sidePanel.padding(.vertical) }
                            .frame(width: 360)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            photoColumn
                            sidePanel
                        }
                        .padding(Theme.pagePadding)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(compose.hasPosted ? "Your week" : "Post your week")
            .toolbar {
                if compose.hasPosted {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete this week", systemImage: Icon.trash, role: .destructive) { confirmDelete = true }
                        } label: {
                            Image(systemName: Icon.more)
                        }
                    }
                }
            }
            .task {
                await compose.load(weekStart: weekStart)
                library.refreshStatus()
                reloadLibrary()
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await compose.importPickerItems(items)
                    pickerItems = []
                }
            }
            .onChange(of: libraryDay) { _, _ in reloadLibrary() }
            .sheet(item: $taggingPhoto) { photo in
                TagPickerSheet(photo: photo, users: compose.taggable) { users in
                    compose.setTags(for: photo.id, users: users)
                }
            }
            .sheet(item: $altPhoto) { photo in
                AltTextSheet(photo: photo) { text in compose.setAltText(for: photo.id, text: text) }
            }
            .sheet(isPresented: $showReorder) {
                ReorderSheet()
            }
            .confirmationDialog("Delete this week's dump?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let id = await compose.delete() { model.feed.remove(dumpID: id) }
                    }
                }
            } message: {
                Text("Your photos and any tags on them are removed. Friends keep the photos they posted.")
            }
        }
    }

    // MARK: - Photos

    private var photoColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let message = compose.errorMessage {
                ErrorBanner(message: message)
            }
            if compose.justPosted {
                Label("Posted. Edit any time until midnight.", systemImage: Icon.done)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            if compose.queuedOffline {
                Label("You're offline. Your week is saved and will post when you're back online.", systemImage: Icon.calendar)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            donePrompt

            if compose.draft.photos.isEmpty {
                emptyPicker
            } else {
                selectedGrid
            }

            librarySection
        }
    }

    private var emptyPicker: some View {
        VStack(spacing: 14) {
            Image(systemName: Icon.photos)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Pick 1 to 15 photos from your week")
                .font(.headline)
            Text(model.clock.rangeLabel(weekStart: weekStart))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: compose.draft.remainingSlots,
                         selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                Label("Choose photos", systemImage: Icon.photos)
            }
            .buttonStyle(.borderedProminent)
            if compose.isImporting { ProgressView() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .card()
        .dropDestination(for: Data.self) { items, _ in
            importDropped(items)
        }
    }

    /// Photos dragged in from Photos, Files or another window go through the same re-encode.
    private func importDropped(_ items: [Data]) -> Bool {
        guard !items.isEmpty, compose.draft.canAddMore else { return false }
        Task {
            for data in items.prefix(compose.draft.remainingSlots) {
                if let processed = await PhotoProcessor.processInBackground(data) {
                    compose.append(processed, takenAt: nil)
                }
            }
        }
        return true
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Theme.gap), count: sizeClass == .regular ? 4 : 3)
    }

    private var selectedGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(compose.draft.photos.count) of \(DumpDraft.maxPhotos)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if compose.draft.photos.count > 1 {
                    Button("Reorder", systemImage: Icon.reorder) { showReorder = true }
                        .font(.subheadline)
                }
            }
            LazyVGrid(columns: columns, spacing: Theme.gap) {
                ForEach(compose.draft.photos) { photo in
                    Button { taggingPhoto = photo } label: {
                        ZStack(alignment: .bottomLeading) {
                            PhotoView(source: photo.source)
                                .aspectRatio(1, contentMode: .fit)
                            if !photo.taggedUsers.isEmpty {
                                Label("\(photo.taggedUsers.count)", systemImage: Icon.tag)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: Capsule())
                                    .padding(6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    .accessibilityLabel(photo.altText.isEmpty ? "Photo, tap to tag friends" : photo.altText)
                    .contextMenu {
                        Button("Tag friends", systemImage: Icon.tag) { taggingPhoto = photo }
                        Button("Alt text", systemImage: Icon.altText) { altPhoto = photo }
                        Button("Remove", systemImage: Icon.trash, role: .destructive) { compose.remove(photo.id) }
                    }
                }
                if compose.draft.canAddMore {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: compose.draft.remainingSlots,
                                 selectionBehavior: .ordered, matching: .images, photoLibrary: .shared()) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).fill(Theme.surface)
                            if compose.isImporting {
                                ProgressView()
                            } else {
                                Image(systemName: Icon.post).font(.title2).foregroundStyle(.secondary)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .accessibilityLabel("Add photos")
                }
            }
            Text("Tap a photo to tag the friends who were there.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .dropDestination(for: Data.self) { items, _ in
            importDropped(items)
        }
    }

    // MARK: - This week's library

    @ViewBuilder
    private var librarySection: some View {
        if library.isAuthorized {
            DisclosureGroup(isExpanded: $showLibrary) {
                WeekLibraryGrid(library: library, columns: columns) { asset in
                    Task {
                        guard let data = await library.imageData(for: asset) else { return }
                        await compose.importLibraryData(data, assetID: asset.localIdentifier, takenAt: asset.creationDate)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text(libraryDay.map { "\(model.clock.weekdayName($0))'s photos" } ?? "This week's photos")
                        .font(.subheadline.weight(.medium))
                    if libraryDay != nil {
                        Button("Show the week") { libraryDay = nil }
                            .font(.subheadline)
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        } else if library.canAsk {
            Button {
                Task {
                    await library.requestAccess()
                    reloadLibrary()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show this week's photos first")
                        .font(.subheadline.weight(.medium))
                    Text("Sundae reads your library to filter to Monday onward. Photos stay on your phone until you post them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }

    private func reloadLibrary() {
        guard library.isAuthorized else { return }
        let cal = model.clock.calendar
        if let day = libraryDay {
            let start = cal.startOfDay(for: day)
            library.loadAssets(from: start, to: cal.date(byAdding: .day, value: 1, to: start) ?? start)
        } else {
            library.loadAssets(from: weekStart, to: model.clock.weekEnd(containing: weekStart))
        }
    }

    /// "You marked the farmers market done on Thursday. Add those photos?"
    @ViewBuilder
    private var donePrompt: some View {
        let done = model.weekday.doneThisWeek(clock: model.clock)
        if !compose.hasPosted, let first = done.first {
            let day = model.clock.weekdayName(first.day)
            VStack(alignment: .leading, spacing: 8) {
                Text("\(day): \u{201C}\(first.suggestion.text)\u{201D}")
                    .font(.subheadline.weight(.medium))
                Text(done.count > 1 ? "You marked \(done.count) ideas done this week. Add those photos?" : "You marked this done. Add those photos?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Show \(day)'s photos") {
                    Task {
                        if library.canAsk { await library.requestAccess() }
                        libraryDay = first.day
                        showLibrary = true
                        reloadLibrary()
                    }
                }
                .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }

    // MARK: - Caption and post

    private var sidePanel: some View {
        @Bindable var store = model.compose
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("How was your week?", text: $store.draft.caption, axis: .vertical)
                    .lineLimit(3...10)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .onChange(of: compose.draft.caption) { _, text in
                        if text.count > DumpDraft.maxCaptionLength { compose.setCaption(text) }
                    }
                if compose.draft.caption.count > DumpDraft.maxCaptionLength - 60 {
                    Text("\(compose.draft.caption.count)/\(DumpDraft.maxCaptionLength)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Toggle("Allow comments", isOn: $store.draft.commentsEnabled)
                .font(.subheadline)

            PrimaryButton(
                title: compose.hasPosted ? "Save changes" : "Post your week",
                isLoading: compose.isSaving,
                isEnabled: compose.canPost && (compose.isDirty || !compose.hasPosted)
            ) {
                Task {
                    if let dump = await compose.save(weekStart: weekStart) {
                        model.feed.insertOwn(dump)
                        model.shared.postedWeekStart = weekStart
                    }
                }
            }
            .keyboardShortcut("n", modifiers: .command)

            Text("Your dump goes to the top of your friends' feeds and into this week on your profile. Tagged friends get a request to approve.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
