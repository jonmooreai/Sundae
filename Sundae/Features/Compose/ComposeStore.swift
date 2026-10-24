import Foundation
import Observation
import PhotosUI
import SwiftUI

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

    /// The Sunday prompt shows once per Sunday until the user posts or waves it away.
    func shouldShowPrompt(weekStart: Date) -> Bool {
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

    /// Loads this week's dump if one exists. An in-progress draft is never thrown away.
    func load(weekStart: Date) async {
        if loadedWeekStart == weekStart, !draft.isEmpty || existingDump != nil { return }
        guard !isLoading else { return }
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
        }
        if queuedOffline { _ = await save(weekStart: weekStart) }
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

    func importLibraryData(_ data: Data, assetID: String, takenAt: Date?) async {
        guard libraryPhotoIDs[assetID] == nil, draft.canAddMore else { return }
        isImporting = true
        defer { isImporting = false }
        guard let processed = await PhotoProcessor.processInBackground(data) else { return }
        let photo = DraftPhoto(source: .data(processed.data), width: processed.width, height: processed.height, takenAt: takenAt)
        libraryPhotoIDs[assetID] = photo.id
        draft.photos.append(photo)
    }

    func removeLibraryAsset(_ assetID: String) {
        guard let id = libraryPhotoIDs.removeValue(forKey: assetID) else { return }
        draft.photos.removeAll { $0.id == id }
    }

    /// Default order is chronological. Photos without a date keep their place at the end.
    func sortChronologically() {
        let dated = draft.photos.filter { $0.takenAt != nil }.sorted { ($0.takenAt ?? .distantPast) < ($1.takenAt ?? .distantPast) }
        guard !dated.isEmpty else { return }
        let undated = draft.photos.filter { $0.takenAt == nil }
        draft.photos = dated + undated
    }

    func append(_ processed: ProcessedPhoto, takenAt: Date?) {
        guard draft.canAddMore else { return }
        let photo = DraftPhoto(source: .data(processed.data), width: processed.width, height: processed.height, takenAt: takenAt)
        // Default order is chronological when we know the dates; otherwise append in pick order.
        if let takenAt, let index = draft.photos.firstIndex(where: { ($0.takenAt ?? .distantPast) > takenAt }) {
            draft.photos.insert(photo, at: index)
        } else {
            draft.photos.append(photo)
        }
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
            let dump = try await api.saveDump(draft, weekStart: weekStart)
            existingDump = dump
            draft = DumpDraft(from: dump)
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

extension DumpDraft {
    init(from dump: Dump) {
        photos = dump.photos.sorted { $0.order < $1.order }.map { photo in
            DraftPhoto(id: photo.id, source: photo.source, width: photo.width, height: photo.height,
                       taggedUsers: photo.visibleTags.map(\.taggedUser), altText: photo.altText ?? "", takenAt: nil)
        }
        caption = dump.caption
        commentsEnabled = dump.commentsEnabled
    }
}
