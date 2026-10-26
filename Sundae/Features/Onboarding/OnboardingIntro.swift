import SwiftUI

/// The first thing anyone sees: the felt sundae from the app icon, the whole screen, before the
/// steps begin. The picture sits on the floor of the screen with its bowl running off the bottom,
/// and the felt's own cream carries on above it, so the picture has no edge.
struct OnboardingIntro: View {
    let onBegin: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// The cream of the felt, taken from the top of the picture.
    static let felt = Color(red: 238 / 255, green: 228 / 255, blue: 212 / 255)

    var body: some View {
        GeometryReader { geo in
            // On iPad the picture stays poster-sized and fades into the felt at its sides.
            let side = min(geo.size.width, 640)
            let topFade: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black, location: 0.12)]
            let sideFade: [Gradient.Stop] = side < geo.size.width - 1
                ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                   .init(color: .black, location: 0.9), .init(color: .clear, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)]
            ZStack {
                Self.felt.ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        Text("Sundae")
                            .font(Theme.display(56))
                        Text("Six days to live it. One day to share it.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(appeared ? 1 : 0)
                    Spacer(minLength: 20)
                    PrimaryButton(title: "Begin", action: onBegin)
                        .frame(maxWidth: 320)
                        .padding(.horizontal, 32)
                        .opacity(appeared ? 1 : 0)
                    Spacer(minLength: 12)
                    Image("SundaeArt")
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .mask { LinearGradient(stops: topFade, startPoint: .top, endPoint: .bottom) }
                        .mask { LinearGradient(stops: sideFade, startPoint: .leading, endPoint: .trailing) }
                        .offset(y: appeared || reduceMotion ? 0 : 28)
                        .accessibilityLabel("A felt ice cream sundae with a cherry on top")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        // Felt is cream in any light; the words on it stay dark.
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { appeared = true }
        }
    }
}
