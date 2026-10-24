import Foundation

/// A dump that could not reach the server, kept on disk until the network returns.
/// Only valid for the week it was composed; a Monday retry is refused by the server anyway.
struct PendingPost: Codable, Sendable {
    var weekStart: Date
    var draft: DumpDraft
    var queuedAt: Date
}

/// Persists at most one pending post, in Application Support, outside any backup.
struct PendingPostStore: Sendable {
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: "Sundae", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "pending-post.json")
    }

    func load() -> PendingPost? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PendingPost.self, from: data)
    }

    func save(_ post: PendingPost) {
        guard let data = try? JSONEncoder().encode(post) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = fileURL
        try? url.setResourceValues(values)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
