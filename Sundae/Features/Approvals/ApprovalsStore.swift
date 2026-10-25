import Foundation
import Observation

@MainActor
@Observable
final class ApprovalsStore {
    private let api: any SundaeAPI
    private(set) var requests: [TagRequest] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var errorMessage: String?

    init(api: any SundaeAPI) {
        self.api = api
    }

    func reset() {
        requests = []
        hasLoaded = false
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            requests = try await api.pendingTagRequests()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Approve adds the photo to the user's week. Decline removes the tag everywhere, quietly.
    func respond(_ request: TagRequest, approve: Bool) async {
        dismiss(request)
        Haptics.light()
        await submit(request, approve: approve)
    }

    /// Takes the request off the list. Wrap in `withAnimation` to let the card leave gracefully.
    func dismiss(_ request: TagRequest) {
        requests.removeAll { $0.id == request.id }
    }

    /// Tells the server; on failure the list reloads so nothing is silently lost.
    func submit(_ request: TagRequest, approve: Bool) async {
        do {
            try await api.respondToTag(id: request.tag.id, approve: approve)
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}
