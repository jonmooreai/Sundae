import SwiftUI

/// A person in a list: round avatar, bold username, one gray line of context. Never wraps.
struct UserRow: View {
    let user: User
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.username)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                let line = subtitle ?? user.searchSubtitle
                if !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}

/// Follow, Requested, Following. A fixed-width pill so rows line up.
struct FollowButton: View {
    let relationship: Relationship
    let action: () -> Void

    var body: some View {
        Group {
            switch relationship {
            case .notFollowing:
                Button(action: action) { Text("Follow").frame(width: 70) }
                    .buttonStyle(.pill(.primary, size: .small))
            case .requested:
                Button(action: action) { Text("Requested").frame(width: 70) }
                    .buttonStyle(.pill(.secondary, size: .small))
            case .following:
                Button(action: action) { Text("Following").frame(width: 70) }
                    .buttonStyle(.pill(.secondary, size: .small))
            case .me, .blocked:
                EmptyView()
            }
        }
        .id(relationship)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .animation(.bouncy(duration: 0.35), value: relationship)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}

/// Large single-purpose button used for the one primary action on each screen.
struct PrimaryButton: View {
    let title: String
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(.white) }
            }
        }
        .buttonStyle(.pill(.primary, fullWidth: true))
        .disabled(!isEnabled || isLoading)
    }
}
