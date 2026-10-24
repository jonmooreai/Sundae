import SwiftUI

/// Likes show as names of friends, not a total, until the count passes 10.
struct LikesLabel: View {
    let dump: Dump
    var meID: ID? = nil

    var body: some View {
        if let text {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var text: String? {
        let likers = dump.likedBy
        if likers.isEmpty { return nil }
        if likers.count > 10 { return "\(likers.count) likes" }
        var names = likers.filter { $0.id != meID }.map(\.firstName)
        if dump.likedByMe { names.insert("you", at: 0) }
        return "Liked by " + ListFormatter.localizedString(byJoining: names)
    }
}
