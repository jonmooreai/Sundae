import Foundation
import Observation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Where the full-screen posting flow starts.
enum ComposeEntry: Equatable {
    /// The Sunday greeting: "It's Sunday. Post your week."
    case prompt
    /// Straight to the photo grid.
    case pick
    /// Editing a dump that already exists.
    case arrange
}

/// The draft lives here, not in a view, so it survives tab switches, the iPad sidebar,
/// and the iPhone Duo unfolding mid-compose.
@MainActor
@Observable
final class ComposeStore {
    private let api: any SundaeAPI
    private let pendingStore = PendingPostStore()
    private static let promptDismissedKey = "sundayPrompt.dismissedWeekStart"
    private static let alwaysPromptKey = "sundayPrompt.always"

    /// Show the full-screen post prompt every time the app opens on Sunday, posted or not.
    var alwaysShowPrompt = UserDefaults.standard.bool(forKey: ComposeStore.alwaysPromptKey) {
        didSet { UserDefaults.standard.set(alwaysShowPrompt, forKey: Self.alwaysPromptKey) }
    }

    /// Whether the full-screen posting flow is on screen, and where it opened.
    private(set) var isPresented = false
    var entry: ComposeEntry = .pick

    var draft = DumpDraft()
    /// Set when a post could not reach the server and is waiting for the network.
    private(set) var queuedOffline = false
    private(set) var existingDump: Dump?
    private(set) var loadedWeekStart: Date?
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var isSaving = false
    private(set) var taggable: [User] = []
    /// Camera roll asset id to the draft photo it became, so the picker can show and undo selections.
    private(set) var libraryPhotoIDs: [String: ID] = [:]
    var justPosted = false
    var errorMessage: String?
    /// The library photos in the post just saved, in its order, for the widget.
    private(set) var postedAssetIDs: [String] = []

    init(api: any SundaeAPI) {
        self.api = api
    }

    var hasPosted: Bool { existingDump != nil }
    var isLocked: Bool { existingDump?.isLocked ?? false }
    var canPost: Bool { !draft.isEmpty && !isSaving && !isLocked }
    var isDirty: Bool {
        guard let existingDump else { return !draft.isEmpty }
        return DumpDraft(from: existingDump) != draft
    }

    func reset() {
        draft = DumpDraft()
        existingDump = nil
        loadedWeekStart = nil
        libraryPhotoIDs = [:]
        justPosted = false
        queuedOffline = false
        errorMessage = nil
    }

    // MARK: - Presentation

    func present(_ entry: ComposeEntry) {
        self.entry = entry
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    /// The Sunday prompt shows once per Sunday until the user posts or waves it away,
    /// or every time when the switch in Settings is on.
    func shouldShowPrompt(weekStart: Date) -> Bool {
        if alwaysShowPrompt { return true }
        guard !hasPosted, !queuedOffline else { return false }
        let dismissed = UserDefaults.standard.object(forKey: Self.promptDismissedKey) as? Date
        return dismissed != weekStart
    }

    func dismissPrompt(for weekStart: Date) {
        UserDefaults.standard.set(weekStart, forKey: Self.promptDismissedKey)
    }

    /// Asset ids of the draft's camera roll photos, in draft order.
    var libraryAssetIDsInOrder: [String] {
        draft.photos.compactMap { photo in libraryPhotoIDs.first { $0.value == photo.id }?.key }
    }

    /// Draft photos that did not come from the camera roll grid (an existing dump, the Photos picker, a drop).
    var nonLibraryPhotoCount: Int {
        draft.photos.count - libraryPhotoIDs.count
    }

    /// Loads this week's dump if one exists. An in-progress draft is never thrown away within its
    /// week. A new week starts from nothing: last week's post and draft can't be posted again, and
    /// the app can sit in memory from one Sunday to the next, so without this Sunday opened on
    /// last week's photos as if they were already this week's post.
    func load(weekStart: Date) async {
        if loadedWeekStart == weekStart, !draft.isEmpty || existingDump != nil { return }
        guard !isLoading else { return }
        if let loaded = loadedWeekStart, loaded != weekStart { reset() }
        isLoading = true
        defer { isLoading = false }
        loadedWeekStart = weekStart
        if let pending = pendingStore.load() {
            if pending.weekStart == weekStart {
                // A post that never reached the server last time. Keep it and try again.
                draft = pending.draft
                queuedOffline = true
            } else {
                pendingStore.clear()
            }
        }
        taggable = (try? await api.taggableUsers()) ?? []
        if let dump = try? await api.myDump(weekStart: weekStart) {
            existingDump = dump
            if draft.isEmpty { draft = DumpDraft(from: dump) }
            Task { await sendMissingFingerprints(of: dump) }
        }
        if queuedOffline { _ = await save(weekStart: weekStart) }
    }

    /// Photos posted before the app sent fingerprints get them now, worked out on this phone from
    /// the posted pictures, so a friend's tag on the same picture shows on this copy instead of a
    /// second one. Once each; quietly does nothing when offline.
    func sendMissingFingerprints(of dump: Dump) async {
        var found: [ID: String] = [:]
        for photo in dump.photos where photo.hasFingerprint == false {
            guard case .remote(let url) = photo.source,
                  let loaded = try? await URLSession.shared.data(from: url) else { continue }
            if let response = loaded.1 as? HTTPURLResponse, response.statusCode >= 400 { continue }
            let data = loaded.0
            if let fingerprint = await Task.detached(priority: .utility, operation: { PhotoFingerprint.of(data) }).value {
                found[photo.id] = fingerprint
            }
        }
        try? await api.setFingerprints(found)
    }

    func refreshTaggable() async {
        taggable = (try? await api.taggableUsers()) ?? []
    }

    // MARK: - Photos

    func importPickerItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        for item in items.prefix(draft.remainingSlots) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let processed = await PhotoProcessor.processInBackground(data) else { continue }
            append(processed, takenAt: nil)
        }
    }

    /// A photo just taken with the camera. Made into a JPEG and then through PhotoProcessor like
    /// every other photo, so it is sized and stripped of its details the same way.
    func addCameraPhoto(_ image: UIImage) async {
        guard draft.canAddMore, let data = image.jpegData(compressionQuality: 0.92) else { return }
        isImporting = true
        defer { isImporting = false }
        guard let processed = await PhotoProcessor.processInBackground(data) else { return }
        append(processed, takenAt: Date())
    }

    func importLibraryData(_ data: Data, assetID: String, takenAt: Date?) async {
        guard libraryPhotoIDs[assetID] == nil, draft.canAddMore else { return }
        isImporting = true
        defer { isImporting = false }
        guard let processed = await PhotoProcessor.processInBackground(data) else { return }
        let photo = DraftPhoto(source: .data(processed.data), width: processed.width, height: processed.height, takenAt: takenAt)
        libraryPhotoIDs[assetID] = photo.id
        draft.photos.append(photo)
    }

    /// Sunday's head start: the photos kept with saved ideas, in the order taken, each starting
    /// with its idea's caption. Only into an empty draft, so nothing anyone picked is replaced.
    func startFromSaved(_ photos: [SavedPhotoForPost], library: PhotoLibrary) async {
        guard draft.isEmpty, existingDump == nil else { return }
        let assets = PhotoFinder.assets(photos.map(\.assetID))
        for photo in photos {
            guard let asset = assets[photo.assetID], let data = await library.imageData(for: asset) else { continue }
            await importLibraryData(data, assetID: photo.assetID, takenAt: asset.creationDate ?? photo.takenAt)
            if !photo.caption.isEmpty, let id = libraryPhotoIDs[photo.assetID] {
                setPhotoCaption(for: id, text: photo.caption)
            }
        }
        sortChronologically()
    }

    func removeLibraryAsset(_ assetID: String) {
        guard let id = libraryPhotoIDs.removeValue(forKey: assetID) else { return }
        draft.photos.removeAll { $0.id == id }
    }

    /// Saved ideas' photos arrive in the order taken. Photos without a date keep their place at the end.
    func sortChronologically() {
        let dated = draft.photos.filter { $0.takenAt != nil }.sorted { ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast) }
        guard !dated.isEmpty else { return }
        let undated = draft.photos.filter { $0.takenAt == nil }
        draft.photos = dated + undated
    }

    /// At the end: photos keep the order they were picked in.
    func append(_ processed: ProcessedPhoto, takenAt: Date?) {
        guard draft.canAddMore else { return }
        draft.photos.append(DraftPhoto(source: .data(processed.data), width: processed.width, height: processed.height, takenAt: takenAt))
    }

    /// The camera roll photos in the order they were tapped, in the places camera roll photos
    /// hold in the draft, so a photo from the camera or another album stays where it is.
    func orderLibraryPhotos(_ assetIDs: [String]) {
        let wanted = assetIDs.compactMap { libraryPhotoIDs[$0] }
        let slots = draft.photos.indices.filter { wanted.contains(draft.photos[$0].id) }
        guard slots.count == wanted.count else { return }
        let byID = Dictionary(draft.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (slot, id) in zip(slots, wanted) {
            if let photo = byID[id] { draft.photos[slot] = photo }
        }
    }

    /// Dropped on another photo in the strip: it takes that photo's place, and the ones between
    /// move along by one.
    func movePhoto(_ id: ID, to target: ID) {
        guard let from = draft.photos.firstIndex(where: { $0.id == id }),
              let to = draft.photos.firstIndex(where: { $0.id == target }), from != to else { return }
        draft.photos.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// The pixels the editor starts from: the photo before any edits, fetched when it is
    /// already posted. Nil for a demo placeholder, or when it cannot be loaded.
    func editableData(for photo: DraftPhoto) async -> Data? {
        switch photo.original?.source ?? photo.source {
        case .data(let data): return data
        case .remote(let url):
            guard let loaded = try? await URLSession.shared.data(from: url) else { return nil }
            if let response = loaded.1 as? HTTPURLResponse, response.statusCode >= 400 { return nil }
            return loaded.0
        case .placeholder: return nil
        }
    }

    /// The editor's result. Edited, the photo becomes the new picture, keeping the one it came
    /// from; untouched again, it goes back to that. Either way it gets a new id, so a picture
    /// half sent before the change is never posted in its place, and a posted photo that was
    /// edited says which one it replaces, so its tags and their answers carry over.
    func applyEdits(to id: ID, edits: PhotoEdits, rendered: ProcessedPhoto?) {
        guard let index = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        var photo = draft.photos[index]
        let original = photo.original ?? DraftOriginal(source: photo.source, width: photo.width, height: photo.height)
        let newID: ID
        if let rendered, !edits.isUntouched {
            if photo.replaces == nil, case .remote = original.source { photo.replaces = photo.id }
            photo.source = .data(rendered.data)
            photo.width = rendered.width
            photo.height = rendered.height
            photo.original = original
            photo.edits = edits
            newID = UUID().uuidString
        } else {
            guard photo.original != nil else { return }
            photo.source = original.source
            photo.width = original.width
            photo.height = original.height
            photo.original = nil
            photo.edits = nil
            // A posted photo put back is the posted photo again.
            newID = photo.replaces ?? UUID().uuidString
            photo.replaces = nil
        }
        let oldID = photo.id
        photo.id = newID
        draft.photos[index] = photo
        for (asset, photoID) in libraryPhotoIDs where photoID == oldID { libraryPhotoIDs[asset] = newID }
    }

    func remove(_ id: ID) {
        draft.photos.removeAll { $0.id == id }
        libraryPhotoIDs = libraryPhotoIDs.filter { $0.value != id }
    }

    func move(from source: IndexSet, to destination: Int) {
        draft.photos.move(fromOffsets: source, toOffset: destination)
    }

    func setTags(for id: ID, users: [User]) {
        guard let index = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        draft.photos[index].taggedUsers = Array(users.prefix(DumpDraft.maxTagsPerPhoto))
    }

    func setAltText(for id: ID, text: String) {
        guard let index = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        draft.photos[index].altText = text
    }

    func setPhotoCaption(for id: ID, text: String) {
        guard let index = draft.photos.firstIndex(where: { $0.id == id }) else { return }
        draft.photos[index].caption = String(text.prefix(DumpDraft.maxPhotoCaptionLength))
    }

    func setCaption(_ text: String) {
        draft.caption = String(text.prefix(DumpDraft.maxCaptionLength))
    }

    // MARK: - Post

    func save(weekStart: Date) async -> Dump? {
        guard canPost else { return nil }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let sent = draft.photos.map(\.id)
            let edited = Set(draft.photos.filter { $0.edits != nil }.map(\.id))
            let dump = try await api.saveDump(draft, weekStart: weekStart)
            existingDump = dump
            draft = DumpDraft(from: dump)
            // The photos now have the server's ids, in the same order: the camera roll photos
            // follow them, so the grid still shows them picked and the widget knows them.
            let saved = draft.photos.map(\.id)
            if sent.count == saved.count {
                let renamed = Dictionary(zip(sent, saved), uniquingKeysWith: { first, _ in first })
                libraryPhotoIDs = libraryPhotoIDs.compactMapValues { renamed[$0] }
                // An edited photo is not the library's picture any more, so the widget leaves it out.
                postedAssetIDs = zip(sent, saved).compactMap { old, new in
                    edited.contains(old) ? nil : libraryPhotoIDs.first { $0.value == new }?.key
                }
            } else {
                postedAssetIDs = []
            }
            justPosted = true
            queuedOffline = false
            pendingStore.clear()
            NotificationScheduler.cancelLastCallForThisWeek()
            Haptics.success()
            return dump
        } catch SundaeError.offline {
            // Compose works offline. Keep the draft on disk and post when the network returns.
            pendingStore.save(PendingPost(weekStart: weekStart, draft: draft, queuedAt: Date()))
            queuedOffline = true
            errorMessage = nil
            return nil
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            return nil
        }
    }

    /// Called when the network comes back. Posts the queued dump if it is still this week.
    func retryQueuedPost(currentWeekStart: Date, isSunday: Bool) async -> Dump? {
        guard queuedOffline, !isSaving else { return nil }
        guard isSunday, loadedWeekStart == currentWeekStart else {
            // Sunday ended before the network came back. The missed week stays empty, by design.
            pendingStore.clear()
            queuedOffline = false
            errorMessage = SundaeError.dumpLocked.localizedDescription
            return nil
        }
        return await save(weekStart: currentWeekStart)
    }

    func delete() async -> ID? {
        guard let dump = existingDump else { return nil }
        do {
            try await api.deleteDump(id: dump.id)
            let weekStart = loadedWeekStart
            reset()
            loadedWeekStart = weekStart
            return dump.id
        } catch {
            if !error.isCancellation { errorMessage = error.localizedDescription }
            return nil
        }
    }
}

extension DumpDraft {
    init(from dump: Dump) {
        photos = dump.photos.sorted { $0.order < $1.order }.map { photo in
            DraftPhoto(id: photo.id, source: photo.source, width: photo.width, height: photo.height,
                       // A friend's tag shown on this copy is theirs, not one to send back as the author's.
                       taggedUsers: photo.visibleTags.filter { !$0.isShared }.map(\.taggedUser), altText: photo.altText ?? "", takenAt: nil,
                       caption: photo.caption ?? "")
        }
        caption = dump.caption
        commentsEnabled = dump.commentsEnabled
    }
}
