import AVFoundation
import Combine
import SwiftUI
import UIKit

/// The first thing anyone sees: the felt sundae building itself, bowl to cherry, in ten seconds.
/// It plays once and rests on the finished sundae, then Begin appears; a tap skips to the end.
/// With Reduce Motion or VoiceOver on, the finished sundae shows as a still and Begin is ready.
/// The sound follows the ring switch and never plays over something already playing.
struct OnboardingIntro: View {
    let onBegin: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var player: AVPlayer?
    @State private var skipped = false
    @State private var finished = false
    @State private var appeared = false

    /// The felt at the top and the foot of the film, so the space around it carries on.
    static let feltTop = Color(red: 229 / 255, green: 221 / 255, blue: 205 / 255)
    static let feltBottom = Color(red: 210 / 255, green: 199 / 255, blue: 182 / 255)
    /// Room under the film for the line and the button, home indicator included.
    private static let bottomRoom: CGFloat = 136

    private var showsStill: Bool { reduceMotion || voiceOver || skipped }

    var body: some View {
        ZStack {
            filmLayer
            VStack(spacing: 0) {
                Text("Sundae")
                    .font(Theme.display(44))
                    .padding(.top, 6)
                    .opacity(appeared ? 1 : 0)
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
                .opacity(finished ? 1 : 0)
                .allowsHitTesting(finished)
                .accessibilityHidden(!finished)
            }
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

    /// The film full width from the top of the screen, fading into the felt below it. Where the
    /// screen is too wide or too short for that, it narrows and fades into the felt at its sides.
    private var filmLayer: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, max(0, geo.size.height - Self.bottomRoom) * 9 / 16)
            let bottomFade: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: 0.92),
                                               .init(color: .clear, location: 1)]
            let sideFade: [Gradient.Stop] = width < geo.size.width - 1
                ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                   .init(color: .black, location: 0.9), .init(color: .clear, location: 1)]
                : [.init(color: .black, location: 0), .init(color: .black, location: 1)]
            ZStack(alignment: .top) {
                LinearGradient(colors: [Self.feltTop, Self.feltBottom], startPoint: .top, endPoint: .bottom)
                film
                    .frame(width: width, height: width * 16 / 9)
                    .clipped()
                    .mask { LinearGradient(stops: bottomFade, startPoint: .top, endPoint: .bottom) }
                    .mask { LinearGradient(stops: sideFade, startPoint: .leading, endPoint: .trailing) }
                    .accessibilityElement()
                    .accessibilityLabel("A felt ice cream sundae, built scoop by scoop, with a cherry on top")
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { appeared = true }
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { finished = true }
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
