import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The first thing anyone sees: the felt sundae building itself, bowl to cherry, in ten seconds,
/// filling the screen. When it ends, the finished sundae rises and settles between the title and
/// Begin, and the felt comes up at the foot of the screen so the words read clearly. A tap skips
/// to the end. With Reduce Motion or VoiceOver on, the finished sundae shows as a still, in place.
/// The sound follows the ring switch and never plays over something already playing.
struct OnboardingIntro: View {
    let onBegin: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var player: AVPlayer?
    @State private var skipped = false
    @State private var finished = false

    /// The felt at the top and the foot of the film, so the space around it carries on.
    static let feltTop = Color(red: 229 / 255, green: 221 / 255, blue: 205 / 255)
    static let feltBottom = Color(red: 210 / 255, green: 199 / 255, blue: 182 / 255)
    /// Where the sundae sits in the film, as fractions of its height: the cherry's stem to the
    /// bowl's foot.
    private static let sundaeTop: CGFloat = 0.18
    private static let sundaeBottom: CGFloat = 0.92
    /// Room inside the safe area for the title above the sundae, and the line and Begin below it.
    private static let titleRoom: CGFloat = 70
    private static let buttonsRoom: CGFloat = 124

    private var showsStill: Bool { reduceMotion || voiceOver || skipped }
    private var settle: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.9) }

    var body: some View {
        ZStack {
            filmLayer
            VStack(spacing: 0) {
                Text("Sundae")
                    .font(Theme.display(44))
                    .padding(.top, 6)
                Spacer(minLength: 0)
                VStack(spacing: 14) {
                    Text("Six days to live it. One day to share it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Begin", action: onBegin)
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
            }
            // The words come in once the sundae has started to settle.
            .opacity(finished ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.35), value: finished)
            .allowsHitTesting(finished)
            .accessibilityHidden(!finished)
        }
        // Felt is cream in any light; the words on it stay dark.
        .preferredColorScheme(.light)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)) { note in
            guard let item = note.object as? AVPlayerItem, item === player?.currentItem else { return }
            finish()
        }
    }

    /// While it plays, the film is as tall as the screen: edge to edge on a phone, and in the middle
    /// with its sides fading into the felt on anything wider. Once it ends it rises, smaller only if
    /// it has to be, so the whole sundae sits between the title and Begin.
    private var filmLayer: some View {
        GeometryReader { geo in
            let size = geo.size
            let width = size.height * 9 / 16
            let top = geo.safeAreaInsets.top + Self.titleRoom
            let bottom = size.height - geo.safeAreaInsets.bottom - Self.buttonsRoom
            let span: CGFloat = (Self.sundaeBottom - Self.sundaeTop) * size.height
            let fitsHeight: CGFloat = (bottom - top) / span
            let fitsWidth: CGFloat = size.width * 0.96 / (0.8 * width)
            let shrink: CGFloat = min(1, max(0.3, fitsHeight), fitsWidth)
            // Moves the sundae's middle to the middle of the space between the title and Begin.
            let sundaeMiddle: CGFloat = ((Self.sundaeTop + Self.sundaeBottom) / 2 - 0.5) * size.height * shrink
            let rise: CGFloat = (top + bottom) / 2 - size.height / 2 - sundaeMiddle
            // Sides that fall inside the screen fade into the felt: while playing on a wide screen,
            // and once settled wherever the smaller film no longer reaches the edges.
            let faded: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                          .init(color: .black, location: 0.9), .init(color: .clear, location: 1)]
            let solid: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: 1)]
            let playingSides = width < size.width - 1 ? faded : solid
            let settledSides = width * shrink < size.width - 1 ? faded : solid
            ZStack {
                LinearGradient(colors: [Self.feltTop, Self.feltBottom], startPoint: .top, endPoint: .bottom)
                film
                    .frame(width: width, height: size.height)
                    .clipped()
                    // Once it is smaller than the screen, its top and foot melt into the felt.
                    .overlay {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [Self.feltTop, Self.feltTop.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: size.height * 0.06)
                            Spacer(minLength: 0)
                            LinearGradient(colors: [Self.feltBottom.opacity(0), Self.feltBottom], startPoint: .top, endPoint: .bottom)
                                .frame(height: size.height * 0.08)
                        }
                        .opacity(finished ? 1 : 0)
                    }
                    .mask {
                        ZStack {
                            LinearGradient(stops: playingSides, startPoint: .leading, endPoint: .trailing)
                                .opacity(finished ? 0 : 1)
                            LinearGradient(stops: settledSides, startPoint: .leading, endPoint: .trailing)
                                .opacity(finished ? 1 : 0)
                        }
                    }
                    .scaleEffect(finished ? shrink : 1)
                    .offset(y: finished ? rise : 0)
                    .animation(settle, value: finished)
                    .accessibilityElement()
                    .accessibilityLabel("A felt ice cream sundae, built scoop by scoop, with a cherry on top")
                // The felt rising at the foot of the screen, under the line and Begin.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [Self.feltBottom.opacity(0), Self.feltBottom], startPoint: .top, endPoint: .bottom)
                        .frame(height: 72)
                    Self.feltBottom
                        .frame(height: max(0, size.height - bottom - 48))
                }
                .opacity(finished ? 1 : 0)
                .animation(settle, value: finished)
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .onTapGesture { if !finished { skip() } }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var film: some View {
        if showsStill {
            Image("IntroFinal").resizable().scaledToFill()
        } else if let player {
            FilmView(player: player)
        } else {
            // The film opens on empty felt, so the felt behind it stands in until it starts.
            Color.clear
        }
    }

    private func start() {
        guard !showsStill, player == nil,
              let url = Bundle.main.url(forResource: "IntroFilm", withExtension: "mp4") else {
            finish()
            return
        }
        // Ambient: silent when the ring switch is, and mixed rather than interrupting. If
        // something else is already playing, the film plays without its sound.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default)
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        player.isMuted = session.isOtherAudioPlaying
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil
    }

    private func skip() {
        player?.pause()
        skipped = true
        finish()
    }

    private func finish() {
        finished = true
    }
}

/// An AVPlayerLayer with no controls, filling its frame.
private struct FilmView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
