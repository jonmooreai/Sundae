import SwiftUI

/// Likes show as names of friends, not a total, until the count passes 10. One line.
struct LikesLabel: View {
    let dump: Dump
    var meID: ID? = nil

    var body: some View {
        if let text {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// Up to three names in full; past that, two names and a count; past ten, just the count.
    private var text: String? {
        let likers = dump.likedBy
        if likers.isEmpty { return nil }
        if likers.count > 10 { return "\(likers.count) likes" }
        var names = likers.filter { $0.id != meID }.map(\.firstName)
        if dump.likedByMe { names.insert("you", at: 0) }
        if names.count > 3 {
            let rest = names.count - 2
            return "Liked by \(names[0]), \(names[1]) and \(rest) others"
        }
        return "Liked by " + ListFormatter.localizedString(byJoining: names)
    }
}

/// The heart. Cherry red once liked, with a small bounce as it turns on.
struct LikeButton: View {
    let liked: Bool
    var size: CGFloat = 26
    /// True when this like is the one that takes the week to ten. A cherry drops onto the heart.
    var celebrates = false
    let action: () -> Void

    @State private var pulse = false
    @State private var cherryShown = false
    @State private var cherryLanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Icon(Glyph.heart, weight: liked ? .fill : .regular, size: size)
                .foregroundStyle(liked ? Theme.cherry : .primary)
                .scaleEffect(pulse ? 1.3 : 1)
                .overlay(alignment: .top) {
                    if cherryShown {
                        CherryDot(size: size * 0.5)
                            .offset(y: cherryLanded ? -size * 0.1 : -size * 1.6)
                            .opacity(cherryLanded ? 1 : 0.4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Unlike" : "Like")
        .onChange(of: liked) { _, now in
            guard now, !reduceMotion else { return }
            withAnimation(.bouncy(duration: 0.3)) { pulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.bouncy(duration: 0.3)) { pulse = false }
            }
            if celebrates { dropCherry() }
        }
    }

    private func dropCherry() {
        cherryShown = true
        cherryLanded = false
        withAnimation(.bouncy(duration: 0.55, extraBounce: 0.25).delay(0.1)) { cherryLanded = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1600))
            withAnimation(.easeOut(duration: 0.35)) { cherryShown = false }
        }
    }
}
