import SwiftUI

/// A cherry-red wax seal with an initial. Approving a tag stamps one onto the tagger's post,
/// where only they see it.
struct WaxSeal: View {
    let initial: String
    var size: CGFloat = 40
    var delay: Double = 0
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Theme.cherry)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5).padding(4)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-8))
        .shadow(color: Theme.cherry.opacity(0.35), radius: 6, y: 3)
        .scaleEffect(stamped ? 1 : 1.7)
        .opacity(stamped ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { stamped = true; return }
            withAnimation(.bouncy(duration: 0.45, extraBounce: 0.2).delay(delay)) { stamped = true }
            Task {
                try? await Task.sleep(for: .seconds(delay + 0.2))
                Haptics.light()
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Maya and Theo approved your tags" with their seals, once, on your own post.
struct SealRow: View {
    @Environment(AppModel.self) private var model
    let dump: Dump
    @State private var fresh: [Tag] = []

    var body: some View {
        if !fresh.isEmpty {
            HStack(spacing: 12) {
                HStack(spacing: -10) {
                    ForEach(Array(fresh.enumerated()), id: \.element.id) { index, tag in
                        WaxSeal(initial: String(tag.taggedUser.initials.prefix(1)), delay: 0.15 + Double(index) * 0.18)
                    }
                }
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .onDisappear { markSeen() }
        } else {
            Color.clear.frame(height: 0).onAppear { fresh = freshTags() }
        }
    }

    private var line: String {
        let names = fresh.map(\.taggedUser.firstName)
        let joined = ListFormatter.localizedString(byJoining: names)
        return names.count == 1 ? "\(joined) approved your tag." : "\(joined) approved your tags."
    }

    /// Approved this week, by people you tagged, not yet celebrated. One seal per person.
    private func freshTags() -> [Tag] {
        guard dump.author.id == model.currentUser?.id else { return [] }
        let seen = MomentMemory.seenSeals
        var people = Set<ID>()
        return dump.photos.flatMap(\.tags).filter { tag in
            guard tag.status == .approved, let at = tag.respondedAt, at >= model.currentWeekStart,
                  !seen.contains(tag.id) else { return false }
            return people.insert(tag.taggedUser.id).inserted
        }
    }

    private func markSeen() {
        var seen = MomentMemory.seenSeals
        for tag in fresh { seen.insert(tag.id) }
        MomentMemory.seenSeals = seen
    }
}
