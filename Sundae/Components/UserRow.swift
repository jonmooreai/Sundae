import SwiftUI

struct UserRow: View {
    let user: User
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(user: user, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName).font(.body.weight(.medium))
                Text(subtitle ?? "@\(user.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Follow, Requested, Following. Private accounts hold at Requested until the owner accepts.
struct FollowButton: View {
    let relationship: Relationship
    let action: () -> Void

    var body: some View {
        switch relationship {
        case .notFollowing:
            Button("Follow", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .requested:
            Button("Requested", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .following:
            Button("Following", action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .me, .blocked:
            EmptyView()
        }
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
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled || isLoading)
    }
}
