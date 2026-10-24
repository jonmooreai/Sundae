import Foundation
import Observation
import PhotosUI
import SwiftUI

/// The draft lives here, not in a view, so it survives tab switches, the iPad sidebar,
/// and the iPhone Duo unfolding mid-compose.
@MainActor
@Observable
final class ComposeStore {
    private let api: any SundaeAPI

    var draft = DumpDraft()
    private(set) var existingDump: Dump?
    private(set) var loadedWeekStart: Date?
    private(set) var isLoading = false
    private(set) var isImporting = false
    private(set) var isSaving = false
    private(set) var taggable: [User] = []
    private(set) var importedAssetIDs: Set<String> = []
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
        importedAssetIDs = []
        justPosted = false
        errorMessage = nil
    }

    /// Loads this week's dump if one exists. An in-progress draft is never thrown away.
    func load(weekStart: Date) async {
        if loadedWeekStart == weekStart, !draft.isEmpty || existingDump != nil { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        loadedWeekStart = weekStart
        taggable = (try? await api.taggableUsers()) ?? []
        if let dump = try? await api.myDump(weekStart: weekStart) {
            existingDump = dump
            if draft.isEmpty { draft = DumpDraft(from: dump) }
        }
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
        guard !importedAssetIDs.contains(assetID), draft.canAddMore else { return }
        isImporting = true
        defer { isImporting = false }
        guard let processed = await PhotoProcessor.processInBackground(data) else { return }
        importedAssetIDs.insert(assetID)
        append(processed, takenAt: takenAt)
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
            NotificationScheduler.cancelLastCallForThisWeek()
            Haptics.success()
            return dump
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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
