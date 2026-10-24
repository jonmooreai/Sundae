import SwiftUI

struct AvatarView: View {
    let user: User
    var size: CGFloat = 40

    var body: some View {
        Group {
            switch user.avatar {
            case .data, .remote:
                PhotoView(source: user.avatar!)
            case .placeholder(let seed):
                ZStack {
                    SeedColor.color(seed)
                    Text(user.initials)
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            case nil:
                ZStack {
                    Theme.surface
                    Image(systemName: Icon.person)
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
